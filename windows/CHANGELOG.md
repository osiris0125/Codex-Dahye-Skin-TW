# 變更紀錄

## 1.0.1

- Windows 啟動、CDP 身分、狀態 schema 3、日誌與回滾流程對齊上游 Codex Dream Skin。
- 修正 Codex 關閉與重新啟動之間的競態、嚴格模式空集合錯誤，以及 injector 讀取區塊外命令列參數的實機錯誤。
- 復原基線新增共用、UTF-8 與 state 相依檔雜湊；restore 完全排除 `config.toml` 與 `appearanceTheme`。
- 新增 Windows skill／agent 入口、雙色即時 DOM QA、亮暗色後代文字可讀性與可還原截圖驗證。

## 1.0.0

- 首個公開版本。
- 支援亮色與深色主題、繁體中文介面與使用者提供的 PNG 主視覺。
- 採獨立 sibling package、可驗證復原基線及官方 Codex 零檔案改寫設計。
