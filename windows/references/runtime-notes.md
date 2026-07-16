# 執行架構

此專案不修改官方 Codex 安裝檔。啟動器只替官方 Codex 的該次工作階段開啟本機偵錯連接埠，再由本機 Node.js 注入介面樣式；復原時會驗證程序身分、停止該工作階段並重新開啟官方 Codex。

安裝內容位於 `%LOCALAPPDATA%\CodexDahyeSkin\package-v1`，執行狀態與復原基線位於 `%LOCALAPPDATA%\CodexDahyeSkin\runtime`。使用者提供的圖片只會被複製到本機建置與安裝目錄，不應提交到 Git。
