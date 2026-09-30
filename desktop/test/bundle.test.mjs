import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../../', import.meta.url));
test('archive is self-contained and speaks MCP through the bundled entry point', { timeout: 15000 }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'forgegui-mcpb-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const archive = join(root, 'dist/forgegui.mcpb');
  execFileSync('unzip', ['-q', archive, '-d', directory]);
  const files = execFileSync('unzip', ['-Z1', archive], { encoding: 'utf8' }).trim().split('\n');
  assert.deepEqual(files.filter(f => !f.endsWith('/')).sort(), ['README.md', 'SDK-LICENSE', 'manifest.json', 'server/index.mjs']);
  const manifest = JSON.parse(await readFile(join(directory, 'manifest.json')));
  assert.equal(manifest.user_config.forgegui_api_key.sensitive, true);
  assert.equal(manifest.user_config.forgegui_api_key.required, true);
  assert.equal(manifest.server.mcp_config.env.FORGEGUI_API_KEY, '${user_config.forgegui_api_key}');
  const checksum = await readFile(`${archive}.sha256`, 'utf8');
  assert.equal(checksum.split(' ')[0], createHash('sha256').update(await readFile(archive)).digest('hex'));
  const endpoint = JSON.parse(await readFile(join(root, 'release/channels.json'))).channels.production.mcp_url;
  await writeFile(join(directory, 'mock.mjs'), `
    globalThis.fetch = async (url, init) => {
      if (String(url) !== ${JSON.stringify(endpoint)}) throw new Error('Wrong endpoint');
      if (new Headers(init.headers).get('authorization') !== 'Bearer test-only-secret') throw new Error('Missing auth');
      const message = JSON.parse(init.body);
      const result = message.method === 'initialize'
        ? { protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'forgegui', version: '1' } }
        : { tools: [{ name: 'library_search', inputSchema: { type: 'object' } }] };
      return Response.json({ jsonrpc: '2.0', id: message.id, result });
    };
  `);
  const child = spawn(process.execPath, ['--import', join(directory, 'mock.mjs'), join(directory, manifest.server.entry_point)], {
    cwd: directory, env: { PATH: process.env.PATH, FORGEGUI_API_KEY: 'test-only-secret' }, stdio: ['pipe', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());
  let stderr = '';
  let stdout = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  child.stdout.on('data', chunk => { stdout += chunk; });
  const exit = new Promise(resolve => child.on('exit', code => resolve(code)));
  const send = message => child.stdin.write(JSON.stringify({ jsonrpc: '2.0', ...message }) + '\n');
  async function waitFor(count) {
    for (let i = 0; i < 200; i++) {
      const lines = stdout.trim().split('\n').filter(Boolean);
      if (lines.length >= count) return lines.map(JSON.parse);
      if (child.exitCode !== null) break;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    assert.fail(`Bundled server did not respond: ${stderr}`);
  }
  send({ id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'test', version: '1' } } });
  assert.equal((await waitFor(1))[0].result.serverInfo.name, 'forgegui');
  send({ id: 2, method: 'tools/list' });
  assert.equal((await waitFor(2))[1].result.tools[0].name, 'library_search');
  child.stdin.end();
  assert.equal(await exit, 0);
  assert.equal(stderr, '');
});
