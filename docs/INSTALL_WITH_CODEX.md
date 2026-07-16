# 讓 Codex 安裝這個皮膚

## 1. Codex 先做什麼

在 repo 根目錄執行測試。這一步只使用 repo 與 `%TEMP%`，不安裝、不建立捷徑、不重啟 Codex：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\tests\run-tests.ps1
```

成功輸出必須是所有測試 PASS。若有任何失敗，停止安裝並說明第一個失敗原因。

## 2. 海報契約

`-HeroPath` 必須是使用者本機的一張 PNG：

- PNG signature 正確。
- 檔案至少 1 KB、最多 20 MB。
- 使用者確認有權在自己的本機環境使用。
- 安裝腳本只複製到本機 package，不回寫 repo、不 commit、不上傳。

## 3. 安裝

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\install-dahye-skin.ps1 -HeroPath "C:\absolute\path\hero.png"
```

執行順序固定為：圖片驗證 → Store Codex／Node／restore SelfTest → build 到 repo ignored `dist` → manifest 驗證 → atomic sibling install → runtime baseline → 兩個繁中捷徑。此命令不啟動 Codex。

成功後應存在：

- `%LOCALAPPDATA%\CodexDahyeSkin\package-v1`
- `%LOCALAPPDATA%\CodexDahyeSkin\runtime\recovery-baseline.json`
- 桌面「Codex 李多慧繁中皮膚」
- 桌面「恢復官方 Codex 外觀（李多慧皮膚）」

## 4. 使用者另行同意後才啟動

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexDahyeSkin\package-v1\windows\scripts\start-dahye-skin.ps1" -RestartCodex
```

接著驗證 light、dark、首頁、一般 task route、route/reload 與原生卡片／側欄／project／composer 互動。

## 5. 復原

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexDahyeSkin\package-v1\windows\scripts\restore-dahye-skin.ps1"
```

restore 只依 Dahye runtime state 精確停止 injector 與本輪官方 CDP 工作階段、封存 state、確認 port 關閉，再用 AppsFolder 重開官方 Codex。它不讀寫 `config.toml`。
