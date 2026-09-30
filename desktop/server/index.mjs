import { bridge } from './bridge.mjs';

try {
  const connection = await bridge({ apiKey: process.env.FORGEGUI_API_KEY, endpoint: FORGEGUI_ENDPOINT });
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void connection.close(); });
} catch {
  process.stderr.write('ForgeGUI could not start. Configure a valid production API key in extension settings.\n');
  process.exitCode = 1;
}
