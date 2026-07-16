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
  previewScheme: null,
});
assert.equal(
  parseCli(['--verify', '--port', '9435', '--browser-id', 'abc', '--preview-scheme', 'light']).previewScheme,
  'light',
);
assert.throws(
  () => parseCli(['--verify', '--port', '9435', '--browser-id', 'abc', '--preview-scheme', 'sepia']),
  /預覽色彩模式/,
);
assert.equal(commandHasExactToken('node.exe "C:\\Dahye Skin\\injector.mjs" --watch --port 9435', '--port', '9435'), true);
assert.equal(commandHasExactToken('node.exe injector.mjs --watch --port 19435', '--port', '9435'), false);
const source = await fs.readFile(new URL('../scripts/injector.mjs', import.meta.url), 'utf8');
assert.match(source, /connectCodexTargets\(port,\s*timeoutMs,\s*browserId\)/, 'CDP 連線函式必須明確接收 Browser ID');
assert.match(source, /listAppTargets\(port,\s*browserId\)/, 'CDP 目標查詢不得讀取隱藏的全域 options');
assert.match(
  source,
  /connectCodexTargets\(options\.port,\s*options\.timeoutMs,\s*options\.browserId\)/,
  '單次注入必須把已驗證的 Browser ID 傳入連線函式',
);
assert.match(source, /setAttribute\('data-dahye-scheme'/, '亮暗色視覺驗收必須只改即時 DOM 的皮膚屬性');
assert.match(source, /classList\.remove\("dark",\s*"light"/, '亮暗色視覺驗收必須同步官方根節點模式');
assert.match(source, /__CODEX_DAHYE_QA_PREVIEW__/, '亮暗色視覺驗收必須保存原始 DOM 模式');
assert.match(source, /restorePreviewScheme/, '亮暗色截圖完成後必須還原原始 DOM 模式');
assert.match(source, /const PREVIEW_PAINT_SETTLE_MS = 850/, '亮暗色截圖前必須等待 GPU 完成重繪');
for (const field of ['scheme', 'styleCount', 'chromeCount', 'stateCount', 'nativeCardsClickable', 'composerClickable']) {
  assert.match(source, new RegExp(`\\b${field}\\b`), `verify 缺少 ${field}`);
}
console.log('PASS injector.tests.mjs');
