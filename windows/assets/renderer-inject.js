((cssText, heroDataUrl) => {
  const STATE_KEY = '__CODEX_DAHYE_SKIN_STATE__';
  const STYLE_ID = 'codex-dahye-skin-style';
  const CHROME_ID = 'codex-dahye-skin-chrome';
  const ROOT_CLASS = 'codex-dahye-skin';
  const VERSION = '1.0.1';

  function detectDahyeScheme(doc = document, win = window) {
    const root = doc.documentElement;
    const marker = `${root?.dataset?.theme ?? ''} ${root?.className ?? ''}`.toLowerCase();
    if (/(dark|night)/.test(marker)) return 'dark';
    if (/(light|day)/.test(marker)) return 'light';
    const main = doc.querySelector?.('main.main-surface, main, [role="main"]');
    for (const node of [main, root].filter(Boolean)) {
      const style = win.getComputedStyle(node);
      if (style.colorScheme?.includes('dark')) return 'dark';
      if (style.colorScheme?.includes('light')) return 'light';
      const rgb = style.backgroundColor?.match(/[\d.]+/g)?.slice(0, 3).map(Number);
      if (rgb?.length === 3 && rgb.some((value) => value !== 0)) {
        const linear = rgb.map((value) => {
          const channel = value / 255;
          return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
        });
        const luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
        return luminance < 0.38 ? 'dark' : 'light';
      }
    }
    return win.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function handleDahyeImageError(chrome) {
    chrome.dataset.dahyeImageFailed = 'true';
    chrome.querySelectorAll('[data-dahye-image]').forEach((image) => { image.hidden = true; });
  }

  if (globalThis.__DAHYE_TEST__) {
    globalThis.__DAHYE_TEST_EXPORTS__ = { detectDahyeScheme, handleDahyeImageError };
    return;
  }

  window.__CODEX_DAHYE_SKIN_DISABLED__ = false;
  const previous = window[STATE_KEY];
  previous?.observer?.disconnect();
  if (previous?.timer) clearInterval(previous.timer);
  if (previous?.scheduler?.timeout) clearTimeout(previous.scheduler.timeout);
  if (previous?.media && previous?.mediaListener) previous.media.removeEventListener?.('change', previous.mediaListener);

  const clearMarks = () => {
    document.querySelectorAll('[data-dahye-surface],[data-dahye-native-card],[data-dahye-native-composer],[data-dahye-native-project]')
      .forEach((node) => {
        node.removeAttribute('data-dahye-surface');
        node.removeAttribute('data-dahye-native-card');
        node.removeAttribute('data-dahye-native-composer');
        node.removeAttribute('data-dahye-native-project');
      });
    document.querySelectorAll('.dahye-home').forEach((node) => node.classList.remove('dahye-home'));
    document.querySelectorAll('.dahye-home-shell').forEach((node) => node.classList.remove('dahye-home-shell'));
  };

  const findHome = () => {
    const exact = document.querySelector('[role="main"]:has([data-testid="home-icon"])');
    if (exact) return exact;
    const main = document.querySelector('[role="main"], main.main-surface, main');
    const composer = main?.querySelector('textarea, [contenteditable="true"]');
    const cards = main ? [...main.querySelectorAll('button')].filter((button) => button.querySelector('svg')) : [];
    return composer && cards.length >= 2 ? main : null;
  };

  const markNativeSurfaces = (shellMain, home) => {
    clearMarks();
    document.querySelector('aside.app-shell-left-panel, aside')?.setAttribute('data-dahye-surface', 'sidebar');
    shellMain?.setAttribute('data-dahye-surface', 'main');
    if (!home) return;
    home.classList.add('dahye-home');
    shellMain?.classList.add('dahye-home-shell');
    const buttons = [...home.querySelectorAll('.group\\/home-suggestions button, button')]
      .filter((button) => button.querySelector('svg') && button.textContent?.trim())
      .slice(0, 4);
    buttons.forEach((button, index) => button.setAttribute('data-dahye-native-card', String(index + 1)));
    const input = home.querySelector('textarea, [contenteditable="true"]');
    const composer = input?.closest('form, .composer-surface-chrome') ?? input?.parentElement;
    composer?.setAttribute('data-dahye-native-composer', 'true');
    const project = home.querySelector('[data-testid*="project"], button[aria-haspopup="menu"]');
    project?.setAttribute('data-dahye-native-project', 'true');
  };

  const ensureChrome = (shellMain, home) => {
    let chrome = document.getElementById(CHROME_ID);
    if (!chrome || chrome.parentElement !== document.body) {
      chrome?.remove();
      chrome = document.createElement('div');
      chrome.id = CHROME_ID;
      chrome.setAttribute('aria-hidden', 'true');
      chrome.innerHTML = `
        <div class="dahye-theme-bar"><span class="dahye-theme-mark"></span><b>李多慧繁體中文主題</b></div>
        <section class="dahye-hero">
          <div class="dahye-hero-copy"><h1>今天一起完成什麼？</h1><p>跟著節奏，把靈感變成作品。</p></div>
          <div class="dahye-rhythm-ribbon"></div>
          <img class="dahye-hero-image" data-dahye-image src="${heroDataUrl}" alt="">
        </section>
        <figure class="dahye-polaroid"><span class="dahye-tape"></span><img data-dahye-image src="${heroDataUrl}" alt=""></figure>`;
      chrome.querySelectorAll('[data-dahye-image]').forEach((image) => {
        image.addEventListener('error', () => handleDahyeImageError(chrome), { once: true });
      });
      document.body.appendChild(chrome);
    }
    const rect = shellMain.getBoundingClientRect();
    Object.assign(chrome.style, {
      left: `${Math.round(rect.left)}px`,
      top: `${Math.round(rect.top)}px`,
      width: `${Math.round(rect.width)}px`,
      height: `${Math.round(rect.height)}px`,
    });
    chrome.classList.toggle('dahye-home-shell', Boolean(home));
    chrome.dataset.dahyePage = home ? 'home' : 'task';
    return chrome;
  };

  const ensure = () => {
    if (window.__CODEX_DAHYE_SKIN_DISABLED__) return;
    const root = document.documentElement;
    const shellMain = document.querySelector('main.main-surface, main');
    if (!root || !shellMain || !document.body) return;
    root.classList.add(ROOT_CLASS);
    root.setAttribute('data-dahye-scheme', detectDahyeScheme());
    root.style.setProperty('--dahye-art', `url("${heroDataUrl}")`);

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      (document.head || root).appendChild(style);
    }
    if (style.dataset.dahyeVersion !== VERSION) {
      style.textContent = cssText;
      style.dataset.dahyeVersion = VERSION;
    }

    const home = findHome();
    markNativeSurfaces(shellMain, home);
    document.body.dataset.dahyePage = home ? 'home' : 'task';
    ensureChrome(shellMain, home);
  };

  const cleanup = () => {
    window.__CODEX_DAHYE_SKIN_DISABLED__ = true;
    clearMarks();
    const root = document.documentElement;
    root?.classList.remove(ROOT_CLASS);
    root?.removeAttribute('data-dahye-scheme');
    root?.style.removeProperty('--dahye-art');
    document.body?.removeAttribute('data-dahye-page');
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
    const state = window[STATE_KEY];
    state?.observer?.disconnect();
    if (state?.timer) clearInterval(state.timer);
    if (state?.scheduler?.timeout) clearTimeout(state.scheduler.timeout);
    if (state?.media && state?.mediaListener) state.media.removeEventListener?.('change', state.mediaListener);
    delete window[STATE_KEY];
    return true;
  };

  const scheduler = { timeout: null };
  const scheduleEnsure = () => {
    if (scheduler.timeout) clearTimeout(scheduler.timeout);
    scheduler.timeout = setTimeout(() => { scheduler.timeout = null; ensure(); }, 180);
  };
  const observer = new MutationObserver(scheduleEnsure);
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['class', 'style', 'data-theme'],
    childList: true,
    subtree: true,
  });
  const timer = setInterval(ensure, 5000);
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  const mediaListener = scheduleEnsure;
  media.addEventListener?.('change', mediaListener);
  window[STATE_KEY] = { ensure, cleanup, observer, timer, scheduler, media, mediaListener, version: VERSION };
  ensure();
})(__DAHYE_CSS_JSON__, __DAHYE_HERO_DATA_URL__)
