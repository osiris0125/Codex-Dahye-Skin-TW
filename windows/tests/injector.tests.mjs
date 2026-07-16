import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {
  DEFAULT_PORT,
  isAllowedLoopbackWebSocket,
  parseCli,
  commandHasExactToken,
} from '../scripts/injector.mjs';

assert.equal(DEFAULT_PORT, 9435);
assert.equal(isAllowedLoopbackWebSocket('ws://127.0.0.1:9435/devtools/page/abc', 9435), true);
assert.equal(isAllowedLoopbackWebSocket('ws://localhost:9435/devtools/page/abc', 9435), true);
assert.equal(isAllowedLoopbackWebSocket('ws://192.168.1.2:9435/devtools/page/abc', 9435), false);
assert.equal(isAllowedLoopbackWebSocket('ws://127.0.0.1:9335/devtools/page/abc', 9435), false);
assert.deepEqual(parseCli(['--verify', '--port', '9435', '--browser-id', 'abc']), {
  mode: 'verify',
  port: 9435,
  browserId: 'abc',
  screenshot: null,
});
assert.equal(commandHasExactToken('node.exe "C:\\Dahye Skin\\injector.mjs" --watch --port 9435', '--port', '9435'), true);
assert.equal(commandHasExactToken('node.exe injector.mjs --watch --port 19435', '--port', '9435'), false);
const source = await fs.readFile(new URL('../scripts/injector.mjs', import.meta.url), 'utf8');
for (const field of ['scheme', 'styleCount', 'chromeCount', 'stateCount', 'nativeCardsClickable', 'composerClickable']) {
  assert.match(source, new RegExp(`\\b${field}\\b`), `verify 缺少 ${field}`);
}
console.log('PASS injector.tests.mjs');
