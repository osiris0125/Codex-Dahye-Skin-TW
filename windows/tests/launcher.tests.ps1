Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = Join-Path $PSScriptRoot '..\scripts'
$files = @(
  'start-dahye-skin.ps1',
  'verify-dahye-skin.ps1',
  'restore-dahye-skin.ps1'
)

$sources = @{}
foreach ($name in $files) {
  $path = Join-Path $scriptsRoot $name
  if (-not (Test-Path -LiteralPath $path)) { throw "缺少 launcher：$name" }
  $tokens = $null
  $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw "$name PowerShell 語法錯誤：$($errors[0].Message)" }
  $sources[$name] = Get-Content -Raw -LiteralPath $path
}

$start = $sources['start-dahye-skin.ps1']
foreach ($token in @(
  'Assert-NoLegacySkinSession','Assert-DahyeRecoveryBaselineCurrent','Get-DahyeCodexInstall',
  'Get-DahyeNodeRuntime','Select-DahyePort','--remote-debugging-address=127.0.0.1',
  '--remote-debugging-port','Get-DahyeVerifiedCdpIdentity','Stop-DahyeCodex',
  '--watch','--browser-id','Write-DahyeState','--verify','Stop-DahyeRecordedInjector',
  'injector.log','injector-error.log','verify.log'
)) {
  if (-not $start.Contains($token)) { throw "start 缺少安全步驟：$token" }
}

$verify = $sources['verify-dahye-skin.ps1']
foreach ($token in @('Read-DahyeState','Get-DahyeVerifiedCdpIdentity','Get-DahyeCodexInstallFromState','--verify','--browser-id','--screenshot')) {
  if (-not $verify.Contains($token)) { throw "verify 缺少身分步驟：$token" }
}

$restore = $sources['restore-dahye-skin.ps1']
foreach ($token in @('SelfTest','touchesConfig = $false','Stop-DahyeRecordedInjector','Archive-DahyeStateFile','Wait-DahyePortAvailable','Get-DahyeCodexInstallFromState','Start-Process -FilePath $relaunchCodex.Executable')) {
  if (-not $restore.Contains($token)) { throw "restore 缺少復原步驟：$token" }
}

$all = ($sources.Values -join "`n")
foreach ($forbidden in @('appearanceTheme','Set-Content $Config','RestoreConfigBackup','CodexDreamSkin\state.json')) {
  if ($all.Contains($forbidden)) { throw "launcher 含禁用設定行為：$forbidden" }
}

Write-Host 'PASS launcher.tests.ps1'
