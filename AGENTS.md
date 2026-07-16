# Codex agent 安裝契約

當使用者要求安裝或驗證本專案時：

1. 先完整閱讀 `docs/INSTALL_WITH_CODEX.md`。
2. 確認使用者提供一個本機 PNG 絕對路徑；不得下載、搜尋或自行提交真人照片。
3. 先跑 `windows/tests/run-tests.ps1`，通過後才執行安裝。
4. 使用 `windows/scripts/install-dahye-skin.ps1 -HeroPath "<absolute-png-path>"`。
5. 安裝完成只回報結果；未取得明確 restart 同意，不執行 start、不關閉 Codex。
6. restart 同意後才執行 installed `start-dahye-skin.ps1 -RestartCodex`，再跑 verify 與亮暗模式實機驗收。

硬性禁止：

- 不修改 WindowsApps、官方二進位、`app.asar`、`config.toml`、API Key、Base URL 或 `appearanceTheme`。
- 不停止、改寫或封存 Dream/Fiona package、state、程序、備份或捷徑。
- 不把 `windows/assets/dahye-hero.png` 或其他真人照片加入 Git。
- 不硬編碼使用者名稱、桌面路徑、機器專屬 hash 或既有復原工具位置。
- 不使用 AGY／Antigravity。

所有新增可見文字、錯誤訊息與文件使用臺灣繁體中文。任何失敗都要安全停止並保留官方 Codex 可復原。
