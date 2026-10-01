import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

export async function bridge({ apiKey, endpoint, input = process.stdin, output = process.stdout, fetchImpl = fetch, timeoutMs = 120_000 }) {
  if (!apiKey || /[\r\n]/.test(apiKey) || apiKey.trim() !== apiKey) {
    throw new Error('Configure a production ForgeGUI API key in the extension settings.');
  }
  const local = new StdioServerTransport(input, output);
  const remote = new StreamableHTTPClientTransport(new URL(endpoint), {
    requestInit: { headers: { Authorization: `Bearer ${apiKey}` } },
    fetch: (url, init) => fetchImpl(url, {
      ...init,
      redirect: 'error',
      signal: AbortSignal.any([init.signal, AbortSignal.timeout(init.method === 'DELETE' ? 2000 : timeoutMs)].filter(Boolean)),
    }),
    reconnectionOptions: { maxRetries: 0, initialReconnectionDelay: 1000, maxReconnectionDelay: 1000, reconnectionDelayGrowFactor: 1 },
  });
  const pending = new Map();
  let closed = false;
  let initializationId;
  const fail = (id, status) => {
    const timer = pending.get(id);
    if (!timer) return;
    clearTimeout(timer);
    pending.delete(id);
    const message = status === 401 ? 'ForgeGUI authentication failed. Replace the API key in extension settings.'
      : status === 403 ? 'ForgeGUI denied access. Check account permissions and key scopes.'
        : 'ForgeGUI request failed or timed out; outcome may be unknown. Check existing job status before retrying paid work.';
    void local.send({ jsonrpc: '2.0', id, error: { code: -32000, message } });
  };
  remote.onmessage = message => {
    if ('id' in message && !('method' in message)) {
      if (!pending.has(message.id)) return;
      clearTimeout(pending.get(message.id));
      pending.delete(message.id);
      if (message.id === initializationId && message.result?.protocolVersion) {
        remote.setProtocolVersion(message.result.protocolVersion);
      }
    }
    if (!closed) void local.send(message);
  };
  remote.onerror = () => {};
  local.onerror = () => {
    if (!closed) void local.send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Invalid MCP input.' } });
  };
  local.onmessage = message => {
    if (closed) return;
    const isRequest = 'method' in message && 'id' in message;
    if (isRequest) {
      if (pending.has(message.id)) return;
      if (message.method === 'initialize') initializationId = message.id;
      pending.set(message.id, setTimeout(() => fail(message.id), timeoutMs));
    }
    void remote.send(message).catch(error => { if (isRequest) fail(message.id, error.code); });
  };
  const close = async () => {
    if (closed) return;
    closed = true;
    input.off('end', close);
    for (const timer of pending.values()) clearTimeout(timer);
    pending.clear();
    try { await remote.terminateSession(); } catch {}
    await remote.close();
    await local.close();
  };
  input.once('end', close);
  await remote.start();
  await local.start();
  return { close };
}
