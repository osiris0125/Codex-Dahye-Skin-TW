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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexDahyeSkin\package-v1\windows\scripts\apply-dahye-skin.ps1"
```

`apply-dahye-skin.ps1` 會用 Windows 管理介面（WMI）的 `Win32_Process.Create` 建立獨立 worker。worker 的父程序是 Windows 的 `WmiPrvSE.exe`，不屬於即將關閉的 Codex，因此 Codex 關閉後仍能完成重啟。它不建立排程工作、服務、開機啟動或登錄自動執行項目。

重啟後先確認 `%LOCALAPPDATA%\CodexDahyeSkin\runtime\apply-result.json` 的 `pass` 為 `true`，再驗證 light、dark、首頁、一般 task route、route/reload 與原生卡片／側欄／project／composer 互動。若失敗，查看同目錄的 `apply.log` 與 `apply-error.log`；啟動器仍會回滾為未開啟偵錯連接埠的官方 Codex。

## 5. 復原

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexDahyeSkin\package-v1\windows\scripts\restore-dahye-skin.ps1"
```

restore 只依 Dahye runtime state 精確停止 injector 與本輪已驗證的官方 CDP 工作階段、封存 state、確認 port 關閉，再用目前已註冊的官方 Store 執行檔重開 Codex。它不讀寫 `config.toml`。

啟動腳本使用與原 Codex Dream Skin Windows 版同級的程序：

1. 先把重啟工作交給不隨 Codex 關閉的獨立 Windows worker。
2. worker 要求現有 Codex 正常關閉，最多等待 15 秒並持續重新查詢。
3. 只有使用者已同意重啟時，逾時才核對官方執行檔路徑並強制停止。
4. 以 `--remote-debugging-address=127.0.0.1` 與獨立連接埠啟動官方 Store 執行檔。
5. 驗證監聽 PID、Store 路徑、Browser ID、同連接埠 WebSocket 與 Codex renderer 標記後，才啟動 injector。
6. 將交接、標準輸出、錯誤輸出、驗證結果與 schema 3 state 寫入獨立 runtime；任一步失敗就回滾並重新開啟不帶偵錯連接埠的官方 Codex。
