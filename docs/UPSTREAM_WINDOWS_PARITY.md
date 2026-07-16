# 與 Codex Dream Skin 原專案的 Windows 流程對照

本專案以 Fei-Away／Codex-Dream-Skin 的乾淨 Windows 版本為行為基準；本次對照固定在上游 commit `26c6c410e0e0bfc053356474620e17f934f483fc`，避免只憑 README 或舊本機副本猜測。

## 沿用的核心方法

| 項目 | 原專案 | 李多慧繁中版 |
|---|---|---|
| 官方程式 | 動態查找已註冊的 `OpenAI.Codex` Store 套件 | 相同，並驗證 Store 簽章種類與官方 `ChatGPT.exe` 路徑 |
| 關閉流程 | 先 `CloseMainWindow`，輪詢 15 秒，已授權才核對路徑後強制停止 | 相同；另有空集合與 500ms 清理回歸測試 |
| 重啟方式 | 官方執行檔加 `--remote-debugging-address=127.0.0.1` 與獨立 CDP port | 相同；預設 port 改為 9435 |
| CDP 身分 | 驗證監聽 PID、Store 執行檔、Browser ID、同 port loopback WebSocket、Codex page target | 相同 |
| 注入生命週期 | Node watcher 維持 route／reload，記錄 PID、命令列、啟動時間與 Browser ID | 相同，並修正可匯入測試版本的 Browser ID 參數作用域 |
| 失敗回滾 | 停止失敗工作階段並以無偵錯 port 的官方 Codex 重開 | 相同 |
| 直接由 Codex 執行 | CLI 呼叫者使用 `-RestartExisting` | 相同；不要求使用者先手動點捷徑 |

Codex 關閉時，原本呼叫 PowerShell 的工具畫面可能顯示中止。這不等於安裝失敗；應以 runtime state、三份 log、已驗證 CDP 與重啟後的 verify 結果判定。

## 刻意不同的地方

- 命名空間完全獨立：`%LOCALAPPDATA%\CodexDahyeSkin\package-v1` 與 `runtime`，不覆寫 Dream/Fiona。
- 全部使用臺灣繁體中文；UI 主題是李多慧粉絲自用構圖，但公開 repo 不包含真人照片。
- 每位使用者以 `-HeroPath` 提供本機 PNG；圖片只進入本機建置套件，不回寫 Git。
- 不沿用原專案的 base theme／config backup 功能；安裝、啟動、驗證與復原腳本均不讀寫 `config.toml` 或 `appearanceTheme`。
- 安裝前先驗證 restore SelfTest，安裝後把 restore、start、injector、common、UTF-8 helper、state helper 等相依檔全部納入 SHA-256 復原基線。
- 新增 light／dark 即時 DOM QA；切換只供截圖驗收，完成後還原原始 DOM 模式，不寫官方設定。

## 平台範圍

目前公開版本只支援 Windows Microsoft Store 版 Codex。原專案的 macOS 腳本依賴不同的 app bundle、啟動與復原流程，不能把本 Windows PowerShell 套件直接宣稱為 Mac 適用；若未來支援 macOS，應建立獨立的 `macos/` 實作與測試。
