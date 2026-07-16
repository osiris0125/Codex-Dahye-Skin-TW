Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\scripts\common-windows.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

$emptyPortIsAvailable = Test-DahyePortAvailable -Port 19435 -ListenerQuery { param($port) @() }
Assert-True $emptyPortIsAvailable '空的監聽清單必須被判定為可用連接埠。'
$emptyPortHasNoOwner = Test-DahyeCodexPortOwner -Port 19435 -Codex ([pscustomobject]@{ Executable='C:\Store\app\ChatGPT.exe' }) -ListenerQuery { param($port) @() }
Assert-True (-not $emptyPortHasNoOwner) '空的監聽清單不得被判定為 Codex 擁有。'

if (-not (Get-Command Stop-DahyeCodex -ErrorAction SilentlyContinue)) {
  throw '缺少上游同等的 Stop-DahyeCodex 安全關閉流程。'
}

$package = [pscustomobject]@{
  Executable = 'C:\Store\app\ChatGPT.exe'
  PackageRoot = 'C:\Store'
}
$fakeProcess = [pscustomobject]@{ ProcessId = 4242 }

$graceful = [pscustomobject]@{ Polls=0; CloseRequests=0; ForceStops=0; Sleeps=@() }
$gracefulQuery = {
  param($candidate)
  $graceful.Polls++
  if ($graceful.Polls -le 3) { return @($fakeProcess) }
  return @()
}.GetNewClosure()
$gracefulClose = { param($process) $graceful.CloseRequests++ }.GetNewClosure()
$gracefulForce = { param($process) $graceful.ForceStops++ }.GetNewClosure()
$gracefulSleep = { param($milliseconds) $graceful.Sleeps += $milliseconds }.GetNewClosure()

Stop-DahyeCodex -Package $package -AllowForce `
  -ProcessQuery $gracefulQuery -CloseRequest $gracefulClose `
  -ForceStop $gracefulForce -Delay $gracefulSleep -GracePeriodMilliseconds 15000

Assert-True ($graceful.CloseRequests -eq 1) '正常關閉必須先要求一次 CloseMainWindow。'
Assert-True ($graceful.ForceStops -eq 0) '正常退出時不得強制終止程序。'
Assert-True ($graceful.Polls -ge 4) '關閉後必須持續重新查詢，直到程序完全消失。'

$forced = [pscustomobject]@{ Running=$true; CloseRequests=0; ForceStops=0; Sleeps=@() }
$forcedQuery = {
  param($candidate)
  if ($forced.Running) { return @($fakeProcess) }
  return @()
}.GetNewClosure()
$forcedClose = { param($process) $forced.CloseRequests++ }.GetNewClosure()
$forcedStop = {
  param($process)
  $forced.ForceStops++
  $forced.Running = $false
}.GetNewClosure()
$forcedSleep = { param($milliseconds) $forced.Sleeps += $milliseconds }.GetNewClosure()

Stop-DahyeCodex -Package $package -AllowForce `
  -ProcessQuery $forcedQuery -CloseRequest $forcedClose `
  -ForceStop $forcedStop -Delay $forcedSleep -GracePeriodMilliseconds 0

Assert-True ($forced.CloseRequests -eq 1) '強制關閉前仍必須先嘗試正常關閉。'
Assert-True ($forced.ForceStops -eq 1) '逾時後取得明確授權才可強制終止。'
Assert-True ($forced.Sleeps -contains 500) '強制終止後必須保留上游的 500ms 清理等待。'

$startPath = Join-Path $PSScriptRoot '..\scripts\start-dahye-skin.ps1'
$start = Get-Content -Raw -LiteralPath $startPath
foreach ($token in @(
  'Stop-DahyeCodex',
  '--remote-debugging-address=127.0.0.1',
  'Get-DahyeVerifiedCdpIdentity',
  'injector.log',
  'injector-error.log',
  'verify.log',
  '-RedirectStandardOutput',
  '-RedirectStandardError'
)) {
  Assert-True $start.Contains($token) "啟動器缺少上游生命週期契約：$token"
}
Assert-True ($start.IndexOf('Stop-DahyeCodex') -lt $start.IndexOf('Start-Process -FilePath $codex.Executable')) `
  '必須完成舊 Codex 關閉與等待後，才啟動新的 CDP 工作階段。'

$install = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\scripts\install-dahye-skin.ps1')
foreach ($forbidden in @('config.toml','appearanceTheme','Install-DahyeBaseTheme','Restore-DahyeBaseTheme')) {
  Assert-True (-not $install.Contains($forbidden)) "公開安裝流程不得修改設定：$forbidden"
}

Write-Host 'PASS lifecycle-parity.tests.ps1'
