# Codex 李多慧繁體中文皮膚

[![Windows tests](https://github.com/osiris0125/Codex-Dahye-Skin-TW/actions/workflows/ci.yml/badge.svg)](https://github.com/osiris0125/Codex-Dahye-Skin-TW/actions/workflows/ci.yml)

給 Windows Microsoft Store 版 Codex 使用的本機繁體中文外觀皮膚。保留 Codex 原生側欄、功能卡、專案選擇器、任務內容與輸入框，只加入亮／深色 V4 視覺、主題列與使用者自行提供的海報。

這是可讓 Codex agent 自行部署的原始碼專案，不是獨立安裝程式。把一張你有權使用的 PNG 海報路徑填進下面提示，再整段交給自己的 Codex 即可；Codex 可以自行 clone、測試與安裝。

## 直接交給 Codex

```text
請 clone https://github.com/osiris0125/Codex-Dahye-Skin-TW 到新的本機資料夾，
然後讀取 repo 的 AGENTS.md 與 docs/INSTALL_WITH_CODEX.md。
我要安裝 Codex 李多慧繁體中文皮膚；海報 PNG 路徑是「請填入你的圖片絕對路徑」。
先執行全部測試與唯讀 preflight，確認官方 Store Codex、Node.js、復原 SelfTest 和圖片格式都通過。
不得修改 WindowsApps、app.asar、config.toml、API Key、Base URL 或其他 Codex 設定。
我明確同意安裝完成後立刻執行已安裝的 apply-dahye-skin.ps1，
讓目前 Codex 自行關閉並以官方 Store 執行檔重啟；重啟後執行 verify 與亮暗模式驗收。
```

Codex 會執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\install-dahye-skin.ps1 -HeroPath "C:\你的圖片\dahye.png"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexDahyeSkin\package-v1\windows\scripts\apply-dahye-skin.ps1"
```

## 必要條件

- Windows 10/11。
- Microsoft Store 安裝的 `OpenAI.Codex`。
- Node.js 22 以上。
- 一張你有權使用的 PNG 圖片；圖片不會提交到這個 repo。

## 安全邊界

- 只使用本機 `127.0.0.1`／`localhost` CDP。
- 驗證 Store package、Browser ID、PID、Node path、命令列與啟動時間。
- 安裝在 `%LOCALAPPDATA%\CodexDahyeSkin\package-v1`，state 在 `%LOCALAPPDATA%\CodexDahyeSkin\runtime`。
- 不修改官方 Codex 二進位、WindowsApps、`app.asar`、API Key、Base URL、`config.toml` 或 `appearanceTheme`。
- 安裝前先執行 repo 自帶的 restore `-SelfTest`；失敗時不建立正式 package 或捷徑。
- 啟動流程沿用原專案的安全生命週期：先正常關閉、重新查詢程序，必要時才強制停止；再驗證 Store 執行檔、CDP 監聽 PID、Browser ID 與同連接埠 WebSocket。
- 套用器把重啟交給由 Windows WMI 建立的獨立 worker；它不會隨 Codex 關閉而被終止，也不建立排程工作、服務或開機啟動項目。
- Codex 視窗關閉時，呼叫它的工具畫面可能顯示中止；真正結果以 `runtime\apply-result.json`、`state.json`、`injector.log`、`injector-error.log`、`verify.log` 與重啟後 verify 為準。
- Dream/Fiona 注入器仍在執行時只會拒絕啟動，不會停止舊程序。

## 圖片與公開散布

本 repo 不包含李多慧真人照片。每位使用者必須自行提供有權使用的 PNG；請勿把未授權照片 commit、開 PR 或附在 issue。專案名稱與主題不表示李多慧本人、經紀公司、OpenAI 或 Codex 的合作、認證或官方發佈。

## 復原

安裝後可點桌面「恢復官方 Codex 外觀（李多慧皮膚）」；或執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexDahyeSkin\package-v1\windows\scripts\restore-dahye-skin.ps1"
```

完整流程見 [安裝文件](docs/INSTALL_WITH_CODEX.md)；上游方法與本版差異見 [Windows 流程對照](docs/UPSTREAM_WINDOWS_PARITY.md)。

## License

程式碼使用 MIT License。人物照片或其他使用者提供資產不包含在 MIT 授權內。
