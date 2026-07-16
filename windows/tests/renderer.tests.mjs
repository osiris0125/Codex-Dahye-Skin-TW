import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

const rendererPath = new URL('../assets/renderer-inject.js', import.meta.url);
const cssPath = new URL('../assets/dahye-skin.css', import.meta.url);
const rendererSource = await fs.readFile(rendererPath, 'utf8');
const css = await fs.readFile(cssPath, 'utf8');

const makeContext = ({ marker = '', backgroundColor = 'rgba(0, 0, 0, 0)', prefersDark = false } = {}) => {
  const main = {};
  const root = { dataset: { theme: marker }, className: marker };
  const document = {
    documentElement: root,
    querySelector: () => main,
  };
  const context = {
    __DAHYE_TEST__: true,
    document,
    getComputedStyle: (node) => ({
      colorScheme: node === root && marker.includes('dark') ? 'dark' : '',
      backgroundColor,
    }),
    matchMedia: () => ({ matches: prefersDark }),
    console,
  };
  context.window = context;
  context.globalThis = context;
  return context;
};

const evaluate = (options) => {
  const context = makeContext(options);
  const executable = rendererSource
    .replace('__DAHYE_CSS_JSON__', JSON.stringify(css))
    .replace('__DAHYE_HERO_DATA_URL__', JSON.stringify('data:image/png;base64,AA=='));
  vm.runInNewContext(executable, context);
  return context.__DAHYE_TEST_EXPORTS__;
};

assert.equal(evaluate({ marker: 'theme-dark' }).detectDahyeScheme(), 'dark');
assert.equal(evaluate({ backgroundColor: 'rgb(12, 16, 32)' }).detectDahyeScheme(), 'dark');
assert.equal(evaluate({ backgroundColor: 'rgb(251, 248, 245)' }).detectDahyeScheme(), 'light');
assert.equal(evaluate({ prefersDark: true }).detectDahyeScheme(), 'dark');

for (const token of ['bg','sidebar','surface','surface-strong','text','text-muted','accent-fill','accent-text','accent-secondary','border','focus','disabled','shadow']) {
  const matches = css.match(new RegExp(`--dahye-${token}\\s*:`, 'g')) ?? [];
  assert.equal(matches.length, 2, `${token} 必須同時有亮色與深色值`);
}
assert.doesNotMatch(css, /color-scheme\s*:\s*light\s*!important/i);
assert.doesNotMatch(css, /transition\s*:\s*all/i);
assert.match(css, /prefers-reduced-motion:\s*reduce/);
assert.match(css, /pointer-events:\s*none/);
assert.match(css, /object-position:\s*62% 34%/);
assert.match(css, /max-width:\s*1120px/);
assert.match(rendererSource, /李多慧繁體中文主題/);
assert.match(rendererSource, /今天一起完成什麼？/);
assert.match(rendererSource, /跟著節奏，把靈感變成作品。/);
assert.match(rendererSource, /getElementById\(STYLE_ID\)/);
assert.match(rendererSource, /previous\?\.observer\?\.disconnect/);
assert.match(rendererSource, /delete window\[STATE_KEY\]/);
assert.doesNotMatch(rendererSource, /私人粉絲自用|Dream|Fiona|薛凯琪/);

console.log('PASS renderer.tests.mjs');
