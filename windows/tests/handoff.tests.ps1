Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = Join-Path $PSScriptRoot '..\scripts'
$handoffPath = Join-Path $scriptsRoot 'handoff-windows.ps1'
$applyPath = Join-Path $scriptsRoot 'apply-dahye-skin.ps1'

foreach ($path in @($handoffPath, $applyPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "缺少 Codex 關閉後仍可存活的重啟交接腳本：$path"
  }
  $tokens = $null
  $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw "PowerShell 語法錯誤：$($errors[0].Message)" }
}

. $handoffPath

$captured = $null
$creator = {
  param($commandLine)
  $script:captured = $commandLine
  [pscustomobject]@{ ReturnValue = 0; ProcessId = 4242 }
}
$result = Start-DahyeDetachedWorker -WorkerScript 'C:\Skin Folder\apply-dahye-skin.ps1' -Port 19435 -ProcessCreator $creator
if ($result.ProcessId -ne 4242) { throw '交接器未回傳由系統建立的 worker PID。' }
if (-not $captured.Contains('-EncodedCommand')) { throw '交接器必須使用固定內容的編碼命令，避免路徑引號破壞命令列。' }

$encoded = ($captured -split '\s+')[-1]
$decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
foreach ($token in @("& 'C:\Skin Folder\apply-dahye-skin.ps1'", '-DetachedWorker', '-Port 19435')) {
  if (-not $decoded.Contains($token)) { throw "worker 命令缺少：$token" }
}

$failed = $false
try {
  Start-DahyeDetachedWorker -WorkerScript 'C:\Skin\apply-dahye-skin.ps1' -Port 19435 `
    -ProcessCreator { param($commandLine) [pscustomobject]@{ ReturnValue = 8; ProcessId = 0 } } | Out-Null
} catch { $failed = $true }
if (-not $failed) { throw 'WMI 建立 worker 失敗時不得回報成功。' }

$handoffSource = Get-Content -Raw -LiteralPath $handoffPath
$applySource = Get-Content -Raw -LiteralPath $applyPath
foreach ($token in @('Invoke-CimMethod', 'Win32_Process', 'WmiPrvSE')) {
  if (-not $handoffSource.Contains($token)) { throw "handoff 缺少獨立程序契約：$token" }
}
foreach ($token in @(
  'Assert-DahyeRecoveryBaselineCurrent', '[switch]$DetachedWorker', '-RestartExisting',
  'apply-result.json', 'apply.log', 'apply-error.log', 'Write-DahyeJsonAtomic'
)) {
  if (-not $applySource.Contains($token)) { throw "apply 缺少可驗證交接步驟：$token" }
}

$all = $handoffSource + "`n" + $applySource
foreach ($forbidden in @('config.toml', 'appearanceTheme', 'WindowsApps\\', 'app.asar')) {
  if ($all.Contains($forbidden)) { throw "交接腳本含禁用行為：$forbidden" }
}

$preflightSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsRoot 'preflight-windows.ps1')
foreach ($token in @('windows\scripts\apply-dahye-skin.ps1', 'windows\scripts\handoff-windows.ps1')) {
  if (-not $preflightSource.Contains($token)) { throw "復原基線未保護交接腳本：$token" }
}

$packageSource = Get-Content -Raw -LiteralPath (Join-Path $scriptsRoot 'package-windows.ps1')
if (-not $packageSource.Contains("Script='apply-dahye-skin.ps1'")) {
  throw '桌面啟動捷徑必須使用獨立交接器。'
}
if ($packageSource.Contains("Script='start-dahye-skin.ps1'; Extra=' -PromptForRestart'")) {
  throw '桌面啟動捷徑不得再依賴會被 Codex 關閉連帶終止的同步啟動器。'
}

Write-Host 'PASS handoff.tests.ps1'
