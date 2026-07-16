---
name: codex-dahye-skin-tw
description: 為 Windows Microsoft Store 版 Codex 安裝、啟動、驗證、更新或復原李多慧繁體中文外觀皮膚；使用本機回環 CDP，不修改官方安裝包與 Codex 設定。
---

# Codex 李多慧繁體中文皮膚

透過 Chromium 開發者工具協定（CDP）把可復原的視覺層套用到官方 Store 版 Codex。人物海報必須由使用者提供有權使用的本機 PNG；不得從網路自行抓取或加入 Git。

## 固定工作流程

1. 先完整閱讀 repo 根目錄的 `AGENTS.md` 與 `docs/INSTALL_WITH_CODEX.md`。
2. 在 repo 根目錄執行 `windows/tests/run-tests.ps1`。任一測試失敗就停止，不得安裝或重啟。
3. 使用 `windows/scripts/install-dahye-skin.ps1 -HeroPath <絕對 PNG 路徑>` 建置並原子安裝獨立的 `package-v1`。
4. 驗證 `%LOCALAPPDATA%\CodexDahyeSkin\runtime\recovery-baseline.json` 已建立，且復原腳本 `-SelfTest` 通過。
5. 使用者已明確同意重啟後，執行已安裝套件的 `start-dahye-skin.ps1 -RestartExisting`。此步會關閉目前 Codex，再以官方 Store 執行檔與本機回環 CDP 重新啟動。
6. 重啟後執行 `verify-dahye-skin.ps1 -ScreenshotPath <絕對路徑>`，檢查首頁、一般任務頁、原生側欄、四張原生卡片、專案選擇器、輸入框，以及亮色與深色模式。
7. 需要復原時，執行 `restore-dahye-skin.ps1`；它只處理已驗證的 Dahye 工作階段，然後以官方執行檔重新開啟 Codex。

## 不可跨越的邊界

- 不修改、取代或取得 `WindowsApps`、官方 Codex 二進位、簽章或 `app.asar` 的所有權。
- 不讀寫 `config.toml`、API Key、Base URL、`appearanceTheme` 或其他無關 Codex 設定。
- 不停止、改寫、封存或移除 Dream/Fiona 的 package、state、備份、程序或捷徑；偵測到仍在執行時只拒絕啟動。
- CDP 只可綁定 `127.0.0.1`，並必須驗證 Store 套件路徑、監聽 PID、Browser ID、同連接埠 WebSocket 與 Codex 頁面目標。
- 不把參考畫面做成覆蓋整個視窗的假介面。側欄、卡片、專案選擇器、任務內容與輸入框都必須保留為 Codex 原生可互動控制項。
- 所有使用者可見文字與錯誤訊息使用臺灣繁體中文。
- 不使用 AGY／Antigravity。

## 驗證命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1
node --check .\windows\scripts\injector.mjs
node --check .\windows\assets\renderer-inject.js
```

成功的判準不是「程序有啟動」，而是自動測試、復原基線、CDP 身分驗證、注入器驗證與亮暗模式截圖都通過。
