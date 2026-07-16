import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const SKIN_VERSION = "1.0.1";
export const DEFAULT_PORT = 9435;
const PREVIEW_PAINT_SETTLE_MS = 850;
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]", "::1"]);
const BROWSER_ID_PATTERN = /^[A-Za-z0-9._-]{1,200}$/;

class CdpIdentityMismatchError extends Error {}

function parseArgs(argv) {
  const options = {
    port: DEFAULT_PORT,
    mode: "watch",
    timeoutMs: 30000,
    screenshot: null,
    reload: false,
    browserId: null,
    previewScheme: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--port") options.port = Number(argv[++i]);
    else if (arg === "--once") options.mode = "once";
    else if (arg === "--watch") options.mode = "watch";
    else if (arg === "--verify") options.mode = "verify";
    else if (arg === "--remove") options.mode = "remove";
    else if (arg === "--timeout-ms") options.timeoutMs = Number(argv[++i]);
    else if (arg === "--browser-id") options.browserId = argv[++i];
    else if (arg === "--screenshot") options.screenshot = path.resolve(argv[++i]);
    else if (arg === "--preview-scheme") options.previewScheme = argv[++i];
    else if (arg === "--reload") options.reload = true;
    else if (arg === "--self-test") options.mode = "self-test";
    else if (arg === "--check-payload") options.mode = "check-payload";
    else throw new Error(`未知參數：${arg}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) {
    throw new Error(`無效的連接埠：${options.port}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 250 || options.timeoutMs > 120000) {
    throw new Error(`無效的逾時設定：${options.timeoutMs}`);
  }
  if (options.browserId !== null && !BROWSER_ID_PATTERN.test(options.browserId)) {
    throw new Error(`無效的瀏覽器 ID：${options.browserId}`);
  }
  if (options.previewScheme !== null && !["light", "dark"].includes(options.previewScheme)) {
    throw new Error(`無效的預覽色彩模式：${options.previewScheme}`);
  }
  if (options.previewScheme !== null && options.mode !== "verify") {
    throw new Error("--preview-scheme 只能用於驗證模式");
  }
  if (["watch", "once", "verify", "remove"].includes(options.mode) && !options.browserId) {
    throw new Error(`${options.mode} 模式必須提供 --browser-id`);
  }
  return options;
}

function validatedDebuggerUrl(target, port) {
  const url = new URL(target.webSocketDebuggerUrl);
  const pathIsValid = /^\/devtools\/(?:page|browser)\/[A-Za-z0-9._-]{1,200}$/.test(url.pathname);
  if (url.protocol !== "ws:" || !LOOPBACK_HOSTS.has(url.hostname) || Number(url.port) !== port ||
      url.username || url.password || url.search || url.hash || !pathIsValid) {
    throw new Error("已拒絕不符合允許格式的本機回環 CDP WebSocket URL");
  }
  return url.href;
}

/** Return true only for an allowed same-port loopback CDP WebSocket URL. */
export function isAllowedLoopbackWebSocket(value, expectedPort) {
  try {
    validatedDebuggerUrl({ webSocketDebuggerUrl: value }, expectedPort);
    return true;
  } catch {
    return false;
  }
}

/** Parse the stable public CLI fields used by launchers and tests. */
export function parseCli(argv) {
  const parsed = parseArgs(argv);
  return {
    mode: parsed.mode,
    port: parsed.port,
    browserId: parsed.browserId,
    screenshot: parsed.screenshot,
    previewScheme: parsed.previewScheme,
  };
}

/** Match a flag/value pair without accepting substring collisions. */
export function commandHasExactToken(commandLine, flag, value) {
  const tokens = commandLine.match(/"(?:\\.|[^"])*"|\S+/g)?.map((token) => token.replace(/^"|"$/g, "")) ?? [];
  return tokens.some((token, index) => token === flag && tokens[index + 1] === value);
}

function browserIdFromVersion(version, port) {
  const url = validatedDebuggerUrl(version, port);
  const parsed = new URL(url);
  const match = parsed.pathname.match(/^\/devtools\/browser\/([A-Za-z0-9._-]{1,200})$/);
  if (!match || parsed.search || parsed.hash || !BROWSER_ID_PATTERN.test(match[1])) {
    throw new Error("已拒絕無效的 CDP 瀏覽器身分 URL");
  }
  return match[1];
}

function isValidCdpPageTarget(item, port) {
  if (item?.type !== "page" || !item.url?.startsWith("app://") || typeof item.id !== "string" ||
      !BROWSER_ID_PATTERN.test(item.id) || !item.webSocketDebuggerUrl) return false;
  try {
    const debuggerUrl = new URL(validatedDebuggerUrl(item, port));
    return debuggerUrl.pathname === `/devtools/page/${item.id}`;
  } catch {
    return false;
  }
}

class CdpSession {
  constructor(target, port) {
    this.target = target;
    this.ws = new WebSocket(validatedDebuggerUrl(target, port));
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.closed = false;
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        try { this.ws.close(); } catch {}
        reject(new Error("開啟 CDP WebSocket 逾時"));
      }, 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("開啟 CDP WebSocket 失敗")); }, { once: true });
    });
    this.ws.addEventListener("message", (event) => this.onMessage(event));
    this.ws.addEventListener("error", () => this.close());
    this.ws.addEventListener("close", () => {
      this.closed = true;
      for (const waiter of this.pending.values()) {
        clearTimeout(waiter.timeout);
        waiter.reject(new Error("CDP 連線已關閉"));
      }
      this.pending.clear();
    });
    await this.send("Runtime.enable");
    await this.send("Page.enable");
    return this;
  }

  onMessage(event) {
    let message;
    try {
      message = JSON.parse(String(event.data));
    } catch {
      this.close();
      return;
    }
    if (message.id) {
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      clearTimeout(waiter.timeout);
      this.pending.delete(message.id);
      if (message.error) waiter.reject(new Error(`${message.error.message} (${message.error.code})`));
      else waiter.resolve(message.result);
      return;
    }
    for (const listener of this.listeners.get(message.method) ?? []) listener(message.params ?? {});
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) ?? [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("CDP 工作階段已關閉"));
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP 命令逾時：${method}`));
      }, 10000);
      this.pending.set(id, { resolve, reject, timeout });
      try {
        this.ws.send(JSON.stringify({ id, method, params }));
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        reject(error);
      }
    });
  }

  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: false,
    });
    if (result.exceptionDetails) {
      const detail = result.exceptionDetails.exception?.description ?? result.exceptionDetails.text;
      throw new Error(`Renderer 執行失敗：${detail}`);
    }
    return result.result?.value;
  }

  close() {
    for (const waiter of this.pending.values()) {
      clearTimeout(waiter.timeout);
      waiter.reject(new Error("CDP 工作階段已關閉"));
    }
    this.pending.clear();
    if (!this.closed) {
      try { this.ws.close(); } catch {}
    }
    this.closed = true;
  }
}

class BrowserIdentityAnchor {
  constructor(url) {
    this.ws = new WebSocket(url);
    this.closed = false;
    this.ws.addEventListener("close", () => { this.closed = true; });
    this.ws.addEventListener("error", () => {
      this.closed = true;
      try { this.ws.close(); } catch {}
    });
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.close();
        reject(new Error("開啟 CDP 瀏覽器身分 WebSocket 逾時"));
      }, 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(new Error("開啟 CDP 瀏覽器身分 WebSocket 失敗"));
      }, { once: true });
      this.ws.addEventListener("close", () => {
        clearTimeout(timeout);
        reject(new Error("CDP 瀏覽器身分 WebSocket 在啟動期間關閉"));
      }, { once: true });
    });
    if (this.closed) throw new Error("CDP 瀏覽器身分 WebSocket 已關閉");
    return this;
  }

  close() {
    if (!this.closed) {
      try { this.ws.close(); } catch {}
    }
    this.closed = true;
  }
}

async function fetchCdpJson(port, resource) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(`http://127.0.0.1:${port}${resource}`, {
      redirect: "error",
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function listAppTargets(port, expectedBrowserId = null) {
  const targets = await fetchCdpJson(port, "/json/list");
  if (!Array.isArray(targets)) throw new Error("CDP 目標清單不是陣列");
  if (expectedBrowserId) {
    const version = await fetchCdpJson(port, "/json/version");
    const actualBrowserId = browserIdFromVersion(version, port);
    if (actualBrowserId !== expectedBrowserId) {
      throw new CdpIdentityMismatchError(
        `CDP 瀏覽器身分已從 ${expectedBrowserId} 變更為 ${actualBrowserId}`,
      );
    }
  }
  return targets.filter((item) => isValidCdpPageTarget(item, port));
}

async function connectBrowserIdentityAnchor(port, expectedBrowserId) {
  const version = await fetchCdpJson(port, "/json/version");
  const actualBrowserId = browserIdFromVersion(version, port);
  if (actualBrowserId !== expectedBrowserId) {
    throw new CdpIdentityMismatchError(
      `CDP 瀏覽器身分已從 ${expectedBrowserId} 變更為 ${actualBrowserId}`,
    );
  }
  return new BrowserIdentityAnchor(validatedDebuggerUrl(version, port)).open();
}

async function loadPayload() {
  const [css, template, art] = await Promise.all([
    fs.readFile(path.join(root, "assets", "dahye-skin.css"), "utf8"),
    fs.readFile(path.join(root, "assets", "renderer-inject.js"), "utf8"),
    fs.readFile(path.join(root, "assets", "dahye-hero.png")),
  ]);
  const artDataUrl = `data:image/png;base64,${art.toString("base64")}`;
  return template
    .replace("__DAHYE_CSS_JSON__", JSON.stringify(css))
    .replace("__DAHYE_HERO_DATA_URL__", JSON.stringify(artDataUrl));
}

async function probeSession(session) {
  return session.evaluate(`(() => {
    const markers = {
      shell: Boolean(document.querySelector('main.main-surface')),
      sidebar: Boolean(document.querySelector('aside.app-shell-left-panel')),
      composer: Boolean(document.querySelector('.composer-surface-chrome')),
      main: Boolean(document.querySelector('[role="main"]')),
    };
    return {
      markers,
      codex: location.protocol === 'app:' && markers.shell && markers.sidebar && (markers.composer || markers.main),
    };
  })()`);
}

async function connectTarget(target, port) {
  return new CdpSession(target, port).open();
}

async function connectCodexTargets(port, timeoutMs, browserId) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const targets = await listAppTargets(port, browserId);
      const connected = [];
      for (const target of targets) {
        let session;
        try {
          session = await connectTarget(target, port);
          const probe = await probeSession(session);
          if (probe?.codex) connected.push({ target, session, probe });
          else session.close();
        } catch (error) {
          session?.close();
          lastError = error;
        }
      }
      if (connected.length) return connected;
      lastError = new Error("沒有頁面符合預期的 Codex shell 標記");
    } catch (error) {
      if (error instanceof CdpIdentityMismatchError) throw error;
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 350));
  }
  throw new Error(`127.0.0.1:${port} 上沒有已驗證的 Codex renderer：${lastError?.message ?? "逾時"}`);
}

async function applyToSession(session, payload) {
  return session.evaluate(payload);
}

async function removeFromSession(session) {
  return session.evaluate(`(() => {
    window.__CODEX_DAHYE_SKIN_DISABLED__ = true;
    const state = window.__CODEX_DAHYE_SKIN_STATE__;
    if (state?.cleanup) return state.cleanup();
    document.documentElement?.classList.remove('codex-dahye-skin');
    document.documentElement?.style.removeProperty('--dahye-art');
    document.querySelectorAll('.dahye-home').forEach((node) => node.classList.remove('dahye-home'));
    document.querySelectorAll('.dahye-home-shell').forEach((node) => node.classList.remove('dahye-home-shell'));
    document.getElementById('codex-dahye-skin-style')?.remove();
    document.getElementById('codex-dahye-skin-chrome')?.remove();
    delete window.__CODEX_DAHYE_SKIN_STATE__;
    return true;
  })()`);
}

async function verifyRemovedSession(session) {
  return session.evaluate(`(() =>
    !document.documentElement.classList.contains('codex-dahye-skin') &&
    !document.documentElement.style.getPropertyValue('--dahye-art') &&
    !document.querySelector('.dahye-home') &&
    !document.querySelector('.dahye-home-shell') &&
    !document.getElementById('codex-dahye-skin-style') &&
    !document.getElementById('codex-dahye-skin-chrome') &&
    !window.__CODEX_DAHYE_SKIN_STATE__
  )()`);
}

async function applyPreviewScheme(session, scheme) {
  return session.evaluate(`(() => {
    const root = document.documentElement;
    const body = document.body;
    const state = window.__CODEX_DAHYE_SKIN_STATE__;
    state?.observer?.disconnect();
    if (state?.timer) clearInterval(state.timer);
    if (state?.scheduler?.timeout) clearTimeout(state.scheduler.timeout);
    window.__CODEX_DAHYE_QA_PREVIEW__ = {
      rootClassName: root.className,
      rootTheme: root.getAttribute('data-theme'),
      rootColorScheme: root.style.colorScheme,
      bodyClassName: body?.className ?? '',
      bodyTheme: body?.getAttribute('data-theme') ?? null,
      skinScheme: root.getAttribute('data-dahye-scheme'),
    };
    root.classList.remove("dark", "light", "theme-dark", "theme-light");
    root.classList.add(${JSON.stringify(scheme)});
    root.setAttribute('data-theme', ${JSON.stringify(scheme)});
    root.style.colorScheme = ${JSON.stringify(scheme)};
    body?.setAttribute('data-theme', ${JSON.stringify(scheme)});
    root.setAttribute('data-dahye-scheme', ${JSON.stringify(scheme)});
    return root.getAttribute('data-dahye-scheme');
  })()`);
}

async function restorePreviewScheme(session) {
  return session.evaluate(`(() => {
    const snapshot = window.__CODEX_DAHYE_QA_PREVIEW__;
    if (!snapshot) return true;
    const root = document.documentElement;
    const body = document.body;
    root.className = snapshot.rootClassName;
    if (snapshot.rootTheme === null) root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', snapshot.rootTheme);
    root.style.colorScheme = snapshot.rootColorScheme;
    if (body) {
      body.className = snapshot.bodyClassName;
      if (snapshot.bodyTheme === null) body.removeAttribute('data-theme');
      else body.setAttribute('data-theme', snapshot.bodyTheme);
    }
    if (snapshot.skinScheme === null) root.removeAttribute('data-dahye-scheme');
    else root.setAttribute('data-dahye-scheme', snapshot.skinScheme);
    delete window.__CODEX_DAHYE_QA_PREVIEW__;
    return true;
  })()`);
}

async function verifySession(session) {
  return session.evaluate(`(() => {
    const box = (node) => {
      if (!node) return null;
      const r = node.getBoundingClientRect();
      return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
    };
    const home = document.querySelector('.dahye-home');
    const suggestions = home?.querySelector('.group\\\\/home-suggestions') ?? null;
    const cards = suggestions ? [...suggestions.querySelectorAll('button')].map(box) : [];
    const nativeCards = [...document.querySelectorAll('[data-dahye-native-card]')];
    const nativeComposer = document.querySelector('[data-dahye-native-composer], .composer-surface-chrome');
    const chrome = document.getElementById('codex-dahye-skin-chrome');
    const result = {
      installed: document.documentElement.classList.contains('codex-dahye-skin'),
      version: window.__CODEX_DAHYE_SKIN_STATE__?.version ?? null,
      expectedVersion: ${JSON.stringify(SKIN_VERSION)},
      scheme: document.documentElement.getAttribute('data-dahye-scheme'),
      styleCount: document.querySelectorAll('#codex-dahye-skin-style').length,
      chromeCount: document.querySelectorAll('#codex-dahye-skin-chrome').length,
      stateCount: window.__CODEX_DAHYE_SKIN_STATE__ ? 1 : 0,
      stylePresent: Boolean(document.getElementById('codex-dahye-skin-style')),
      chromePresent: Boolean(chrome),
      chromePointerEvents: getComputedStyle(chrome || document.body).pointerEvents,
      nativeCardsClickable: nativeCards.every((node) => getComputedStyle(node).pointerEvents !== 'none'),
      composerClickable: Boolean(nativeComposer) && getComputedStyle(nativeComposer).pointerEvents !== 'none',
      homePresent: Boolean(home),
      suggestionsPresent: Boolean(suggestions),
      hero: box(home?.firstElementChild?.firstElementChild?.firstElementChild),
      cards,
      composer: box(document.querySelector('.composer-surface-chrome')),
      sidebar: box(document.querySelector('aside.app-shell-left-panel')),
      viewport: { width: innerWidth, height: innerHeight },
      documentOverflow: {
        x: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        y: document.documentElement.scrollHeight > document.documentElement.clientHeight,
      },
    };
    result.pass = result.installed && result.version === result.expectedVersion &&
      ['light', 'dark'].includes(result.scheme) && result.styleCount === 1 &&
      result.chromeCount === 1 && result.stateCount === 1 &&
      result.stylePresent && result.chromePresent && result.chromePointerEvents === 'none' &&
      result.nativeCardsClickable && result.composerClickable && Boolean(result.composer) && Boolean(result.sidebar) &&
      (!result.homePresent || (Boolean(result.hero) &&
        (!result.suggestionsPresent || (result.cards.length >= 2 && result.cards.length <= 4))));
    return result;
  })()`);
}

async function waitForVerifiedSession(session, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastResult;
  let lastError;
  while (Date.now() < deadline) {
    try {
      lastResult = await verifySession(session);
      lastError = null;
      if (lastResult.pass) return lastResult;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (!lastResult && lastError) throw lastError;
  return lastResult;
}

async function capture(session, outputPath) {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await session.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  await session.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  const viewport = await session.evaluate("({ width: innerWidth, height: innerHeight })");
  await session.send("Input.dispatchMouseEvent", {
    type: "mouseMoved",
    x: Math.round(viewport.width * 0.64),
    y: Math.round(viewport.height * 0.62),
    button: "none",
  });
  await new Promise((resolve) => setTimeout(resolve, 300));
  const result = await session.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false,
  });
  await fs.writeFile(outputPath, Buffer.from(result.data, "base64"));
}

async function runOneShot(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs, options.browserId);
  const payload = (options.mode === "once" || options.reload || options.previewScheme) ? await loadPayload() : null;
  const results = [];
  let screenshotCaptured = false;
  try {
    for (const { target, session, probe } of connected) {
      try {
        if (options.mode === "remove") await removeFromSession(session);
        else if (options.mode === "once") await applyToSession(session, payload);
        if (options.mode === "once") {
          await new Promise((resolve) => setTimeout(resolve, 850));
        }
        if (options.reload) {
          await session.send("Page.reload", { ignoreCache: true });
          await new Promise((resolve) => setTimeout(resolve, 1600));
          if (options.mode !== "remove") await applyToSession(session, payload);
        }
        if (options.previewScheme) {
          const appliedScheme = await applyPreviewScheme(session, options.previewScheme);
          if (appliedScheme !== options.previewScheme) {
            throw new Error(`預覽色彩模式未套用：${options.previewScheme}`);
          }
          await new Promise((resolve) => setTimeout(resolve, PREVIEW_PAINT_SETTLE_MS));
        }
        const verified = options.mode === "remove"
          ? await verifyRemovedSession(session)
          : (options.reload || options.mode === "once" || options.mode === "verify")
            ? await waitForVerifiedSession(session, options.timeoutMs)
            : await verifySession(session);
        results.push({ targetId: target.id, markers: probe.markers, result: verified });
        if (options.screenshot && !screenshotCaptured) {
          await capture(session, options.screenshot);
          screenshotCaptured = true;
        }
      } finally {
        if (options.previewScheme) {
          await restorePreviewScheme(session);
          await applyToSession(session, payload);
        }
        session.close();
      }
    }
  } finally {
    for (const { session } of connected) session.close();
  }
  console.log(JSON.stringify({ mode: options.mode, port: options.port, targets: results }, null, 2));
  const failed = results.length === 0 || results.some((item) =>
    options.mode === "remove" ? item.result !== true : !item.result?.pass);
  if (failed) process.exitCode = 2;
}

async function runWatch(options) {
  const identityAnchor = await connectBrowserIdentityAnchor(options.port, options.browserId);
  const sessions = new Map();
  const targetFailures = new Map();
  let stopping = false;
  let listFailures = 0;
  let lastListErrorLogAt = 0;
  const stop = () => { stopping = true; };
  const rejectTarget = (target, baseDelayMs, error = null) => {
    const previous = targetFailures.get(target.id) ?? { failures: 0, lastLogAt: 0 };
    const failures = previous.failures + 1;
    const delayMs = Math.min(30000, baseDelayMs * (2 ** Math.min(failures - 1, 4)));
    const now = Date.now();
    if (error && (failures === 1 || now - previous.lastLogAt >= 30000)) {
      console.error(`[dahye-skin] 目標 ${target.id} 注入失敗：${error.message}；${delayMs}ms 後重試`);
      previous.lastLogAt = now;
    }
    targetFailures.set(target.id, { failures, lastLogAt: previous.lastLogAt, until: now + delayMs });
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  try {
    const payload = await loadPayload();
    while (!stopping) {
      if (identityAnchor.closed) {
        console.error("[dahye-skin] 原始 CDP 瀏覽器身分已關閉；監看程序將停止，不會連到其他瀏覽器");
        process.exitCode = 3;
        break;
      }
      let targets = [];
      try {
        targets = await listAppTargets(options.port);
        listFailures = 0;
      } catch (error) {
        listFailures += 1;
        const retryMs = Math.min(10000, 1000 * (2 ** Math.min(listFailures - 1, 4)));
        if (listFailures === 1 || Date.now() - lastListErrorLogAt >= 30000) {
          console.error(`[dahye-skin] ${new Date().toISOString()} ${error.message}；${retryMs}ms 後重試`);
          lastListErrorLogAt = Date.now();
        }
        await new Promise((resolve) => setTimeout(resolve, retryMs));
        continue;
      }

      const activeIds = new Set(targets.map((target) => target.id));
      for (const id of targetFailures.keys()) {
        if (!activeIds.has(id)) targetFailures.delete(id);
      }
      for (const [id, session] of sessions) {
        if (!activeIds.has(id) || session.closed) {
          session.close();
          sessions.delete(id);
          targetFailures.delete(id);
        }
      }

      for (const target of targets) {
        if (identityAnchor.closed) break;
        if (sessions.has(target.id)) continue;
        if ((targetFailures.get(target.id)?.until ?? 0) > Date.now()) continue;
        let session;
        try {
          session = await connectTarget(target, options.port);
          if (identityAnchor.closed) throw new CdpIdentityMismatchError("原始 CDP 瀏覽器身分已關閉");
          const probe = await probeSession(session);
          if (!probe?.codex) {
            rejectTarget(target, 5000);
            session.close();
            continue;
          }
          let lastReinjectErrorLogAt = 0;
          session.on("Page.loadEventFired", () => {
            setTimeout(() => applyToSession(session, payload).catch((error) => {
              if (Date.now() - lastReinjectErrorLogAt >= 30000) {
                console.error(`[dahye-skin] 目標 ${target.id} 重新注入失敗：${error.message}`);
                lastReinjectErrorLogAt = Date.now();
              }
            }), 250);
          });
          if (identityAnchor.closed) throw new CdpIdentityMismatchError("原始 CDP 瀏覽器身分已關閉");
          await applyToSession(session, payload);
          sessions.set(target.id, session);
          targetFailures.delete(target.id);
          console.log(`[dahye-skin] 已注入目標 ${target.id}`);
        } catch (error) {
          session?.close();
          if (identityAnchor.closed || error instanceof CdpIdentityMismatchError) break;
          rejectTarget(target, 2500, error);
        }
      }
      await new Promise((resolve) => setTimeout(resolve, 1200));
    }
  } finally {
    identityAnchor.close();
    for (const session of sessions.values()) session.close();
  }
}

const isMainModule = Boolean(process.argv[1]) && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMainModule) {
const options = parseArgs(process.argv.slice(2));
if (options.mode === "self-test") {
  const valid = validatedDebuggerUrl({ webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/page/test` }, options.port);
  const browserId = browserIdFromVersion({
    webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/browser/test-browser`,
  }, options.port);
  const invalid = [
    "ws://example.com/devtools/page/test",
    `ws://127.0.0.1:${options.port + 1}/devtools/page/test`,
    `wss://127.0.0.1:${options.port}/devtools/page/test`,
    `ws://user@127.0.0.1:${options.port}/devtools/page/test`,
    `ws://127.0.0.1:${options.port}/unexpected/test`,
    `ws://127.0.0.1:${options.port}/devtools/page/test?query=1`,
  ];
  for (const value of invalid) {
    let rejected = false;
    try { validatedDebuggerUrl({ webSocketDebuggerUrl: value }, options.port); } catch { rejected = true; }
    if (!rejected) throw new Error(`CDP URL 驗證錯誤地接受了不安全 URL：${value}`);
  }
  const invalidBrowserUrls = [
    `ws://127.0.0.1:${options.port}/devtools/page/not-a-browser`,
    `ws://127.0.0.1:${options.port}/devtools/browser/bad%20id`,
    `ws://127.0.0.1:${options.port}/devtools/browser/test?query=1`,
  ];
  for (const value of invalidBrowserUrls) {
    let rejected = false;
    try { browserIdFromVersion({ webSocketDebuggerUrl: value }, options.port); } catch { rejected = true; }
    if (!rejected) throw new Error(`瀏覽器身分驗證錯誤地接受了不安全 URL：${value}`);
  }
  const validPageTarget = {
    id: "page-test",
    type: "page",
    url: "app://codex/",
    webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/page/page-test`,
  };
  const invalidPageTargets = [
    { ...validPageTarget, webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/browser/page-test` },
    { ...validPageTarget, id: "other-page" },
    { ...validPageTarget, id: 123 },
    { ...validPageTarget, type: "other" },
  ];
  if (!valid || browserId !== "test-browser" || !isValidCdpPageTarget(validPageTarget, options.port) ||
      invalidPageTargets.some((item) => isValidCdpPageTarget(item, options.port))) {
    throw new Error("CDP URL 與目標驗證自我測試失敗");
  }
  console.log(JSON.stringify({ pass: true, version: SKIN_VERSION, test: "loopback-cdp-validation" }));
} else if (options.mode === "check-payload") {
  const payload = await loadPayload();
  if (payload.includes("__DAHYE_CSS_JSON__") || payload.includes("__DAHYE_HERO_DATA_URL__")) {
    throw new Error("注入內容的預留標記未完整替換");
  }
  console.log(JSON.stringify({ pass: true, version: SKIN_VERSION, payloadBytes: Buffer.byteLength(payload) }));
} else if (options.mode === "watch") await runWatch(options);
else await runOneShot(options);
}
