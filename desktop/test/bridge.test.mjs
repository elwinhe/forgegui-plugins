import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough } from 'node:stream';
import { bridge } from '../server/bridge.mjs';

const key = 'test-only-secret';
const endpoint = 'https://example.invalid/mcp';
const reply = (id, result) => Response.json({ jsonrpc: '2.0', id, result });
async function harness(t, fetchImpl, timeoutMs = 1000) {
  const input = new PassThrough();
  const output = new PassThrough();
  let buffer = '';
  const messages = [];
  output.on('data', chunk => {
    buffer += chunk;
    const lines = buffer.split('\n');
    buffer = lines.pop();
    messages.push(...lines.filter(Boolean).map(JSON.parse));
  });
  const calls = [];
  const connection = await bridge({ apiKey: key, endpoint, input, output, timeoutMs, fetchImpl: async (url, init) => {
    calls.push({ url, init });
    return fetchImpl(url, init);
  } });
  t.after(() => connection.close());
  return { input, output, messages, calls, close: connection.close,
    send(message) { input.write(JSON.stringify({ jsonrpc: '2.0', ...message }) + '\n'); },
    async next(count = 1) {
      await new Promise((resolve, reject) => {
        const deadline = setTimeout(() => { clearInterval(poll); reject(new Error('No response')); }, 2000);
        const poll = setInterval(() => { if (messages.length >= count) { clearInterval(poll); clearTimeout(deadline); resolve(); } }, 5);
      });
      return messages[count - 1];
    },
  };
}
for (const apiKey of [undefined, '', ' padded', 'line\nbreak']) {
  test(`reject invalid key ${JSON.stringify(apiKey)}`, async () => {
    await assert.rejects(bridge({ apiKey, endpoint }), /Configure/);
  });
}
test('preserves initialization capabilities, session and negotiated protocol', async t => {
  const result = { protocolVersion: '2025-03-26', capabilities: { tools: { listChanged: true }, prompts: {}, resources: {} }, serverInfo: { name: 'forgegui', version: '1' } };
  const h = await harness(t, async (_url, init) => {
    if (init.method !== 'POST') return new Response(null, { status: 405 });
    const message = JSON.parse(init.body);
    if (message.method === 'initialize') return Response.json({ jsonrpc: '2.0', id: message.id, result }, { headers: { 'mcp-session-id': 'session-one' } });
    return reply(message.id, { tools: [{ name: 'library_search', inputSchema: { type: 'object' } }] });
  });
  h.send({ id: 1, method: 'initialize', params: {} });
  assert.deepEqual((await h.next()).result, result);
  h.send({ id: 2, method: 'tools/list' });
  assert.equal((await h.next(2)).result.tools[0].name, 'library_search');
  const headers = h.calls[1].init.headers;
  assert.equal(headers.get('authorization'), `Bearer ${key}`);
  assert.equal(headers.get('mcp-session-id'), 'session-one');
  assert.equal(headers.get('mcp-protocol-version'), result.protocolVersion);
  assert.equal(h.calls[0].init.redirect, 'error');
});
test('forwards tool calls and errors unchanged without retries', async t => {
  const result = { content: [{ type: 'text', text: 'Insufficient credits' }], isError: true };
  const h = await harness(t, async (_url, init) => reply(JSON.parse(init.body).id, result));
  const params = { name: 'generate_asset', arguments: { request_id: 'stable-id' } };
  h.send({ id: 'job', method: 'tools/call', params });
  assert.deepEqual((await h.next()).result, result);
  assert.deepEqual(JSON.parse(h.calls[0].init.body).params, params);
  assert.equal(h.calls.length, 1);
});
for (const status of [401, 403, 429, 500]) {
  test(`sanitizes HTTP ${status} without retrying`, async t => {
    const h = await harness(t, async () => new Response(key, { status }));
    h.send({ id: 1, method: 'tools/call', params: {} });
    const message = await h.next();
    assert.equal(message.error.code, -32000);
    assert.ok(!JSON.stringify(message).includes(key));
    assert.match(message.error.message, status === 401 ? /authentication/ : status === 403 ? /permissions/ : /outcome may be unknown/);
    assert.equal(h.calls.length, 1);
  });
}
test('times out and aborts the network request without replay', async t => {
  let aborted = false;
  const h = await harness(t, (_url, init) => new Promise((_resolve, reject) => {
    init.signal.addEventListener('abort', () => { aborted = true; reject(init.signal.reason); }, { once: true });
  }), 30);
  h.send({ id: 1, method: 'tools/call', params: {} });
  assert.match((await h.next()).error.message, /outcome may be unknown/);
  await new Promise(resolve => setTimeout(resolve, 40));
  assert.ok(aborted);
  assert.equal(h.calls.length, 1);
  assert.equal(h.messages.length, 1);
});
test('forwards SSE progress and response', async t => {
  const events = [{ jsonrpc: '2.0', method: 'notifications/progress', params: { progressToken: 1, progress: 1 } }, { jsonrpc: '2.0', id: 1, result: { content: [] } }];
  const h = await harness(t, async () => new Response(events.map(value => `event: message\ndata: ${JSON.stringify(value)}\n\n`).join(''), { headers: { 'content-type': 'text/event-stream' } }));
  h.send({ id: 1, method: 'tools/call' });
  await h.next(2);
  assert.deepEqual(h.messages, events);
});
test('handles malformed stdio and closes idempotently', async t => {
  const h = await harness(t, async () => { throw new Error('Should not fetch'); });
  h.input.write('not-json\n');
  assert.equal((await h.next()).error.code, -32700);
  await h.close();
  await h.close();
  assert.equal(h.calls.length, 0);
});
test('drops late responses after a timeout', async t => {
  const h = await harness(t, async (_url, init) => {
    await new Promise(resolve => setTimeout(resolve, 80));
    return reply(JSON.parse(init.body).id, { content: [] });
  }, 20);
  h.send({ id: 1, method: 'tools/call' });
  assert.match((await h.next()).error.message, /outcome may be unknown/);
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(h.messages.length, 1);
  assert.equal(h.calls.length, 1);
});
test('forwards notifications and server-directed responses without adding requests', async t => {
  const h = await harness(t, async () => new Response(null, { status: 202 }));
  h.send({ method: 'notifications/cancelled', params: { requestId: 3 } });
  h.send({ id: 'server-request', result: {} });
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.equal(h.calls.length, 2);
  assert.equal(JSON.parse(h.calls[0].init.body).method, 'notifications/cancelled');
  assert.equal(JSON.parse(h.calls[1].init.body).id, 'server-request');
  assert.equal(h.messages.length, 0);
});
