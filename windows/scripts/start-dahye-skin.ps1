param(
  [Nullable[int]]$Port,
  [switch]$RestartCodex,
  [switch]$PromptForRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'state-windows.ps1')
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'preflight-windows.ps1')

$mutex = $null
$package = $null
$injector = $null
$selectedPort = $null
$codexLifecycleChanged = $false
$statePath = Join-Path (Get-DahyeStateRoot) 'state.json'
$baselinePath = Join-Path (Get-DahyeStateRoot) 'recovery-baseline.json'
$injectorPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'injector.mjs')).Path

try {
  $mutex = Enter-DahyeOperationLock
  Assert-NoLegacySkinSession
  Assert-DahyeRecoveryBaselineCurrent -BaselinePath $baselinePath
  $package = Get-RegisteredCodexPackage
  $nodePath = Get-DahyeNodePath -MinimumMajor 22
  $selectedPort = Resolve-DahyePort -ExplicitPort $Port -PreferredPort 9435 -ScanCount 100

  $running = @(Get-DahyeCodexProcesses -Package $package)
  if ($running.Count -gt 0 -and -not $RestartCodex) {
    if (-not $PromptForRestart) { throw 'Codex 已開啟；CLI 必須明確加上 -RestartCodex。' }
    $answer = Read-Host 'Codex 已開啟。要關閉後以李多慧皮膚模式重開嗎？輸入 Y 繼續'
    if ($answer -notmatch '^(Y|y|是)$') { throw '使用者取消啟動。' }
  }
  if ($running.Count -gt 0) {
    Stop-DahyeVerifiedCodexProcesses -Package $package -AllVerified
    $codexLifecycleChanged = $true
  }

  Start-Process -FilePath $package.Executable -ArgumentList "--remote-debugging-port=$selectedPort" | Out-Null
  $codexLifecycleChanged = $true
  $browserId = Wait-DahyeBrowserIdentity -Port $selectedPort -TimeoutSeconds 30
  $injector = Start-Process -FilePath $nodePath -ArgumentList @(
    $injectorPath, '--watch', '--port', "$selectedPort", '--browser-id', $browserId
  ) -PassThru -WindowStyle Hidden
  $state = New-DahyeRuntimeState -Port $selectedPort -Injector $injector -InjectorPath $injectorPath `
    -NodePath $nodePath -Package $package -BrowserId $browserId -RecoveryBaselinePath $baselinePath
  Write-DahyeState -State $state -StatePath $statePath

  & $nodePath $injectorPath --verify --port $selectedPort --browser-id $browserId
  if ($LASTEXITCODE -ne 0) { throw '李多慧皮膚注入驗證失敗。' }
  Write-Host "李多慧繁體中文 Codex 皮膚已啟動（本機連接埠 $selectedPort）。"
} catch {
  Invoke-DahyeStartRollback -Injector $injector -Package $package -Port $selectedPort -StatePath $statePath -RelaunchOfficial:$codexLifecycleChanged
  throw
} finally {
  Exit-DahyeOperationLock -Mutex $mutex
}
