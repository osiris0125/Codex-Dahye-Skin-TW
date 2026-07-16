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
  'Assert-NoLegacySkinSession','Assert-DahyeRecoveryBaselineCurrent','Get-RegisteredCodexPackage',
  'Get-DahyeNodePath','Resolve-DahyePort','--remote-debugging-port','Wait-DahyeBrowserIdentity',
  '--watch','--browser-id','Write-DahyeState','--verify','Invoke-DahyeStartRollback',
  '-RelaunchOfficial:$codexLifecycleChanged'
)) {
  if (-not $start.Contains($token)) { throw "start 缺少安全步驟：$token" }
}

$verify = $sources['verify-dahye-skin.ps1']
foreach ($token in @('Read-DahyeState','Test-DahyeRecordedProcess','--verify','--browser-id','--screenshot')) {
  if (-not $verify.Contains($token)) { throw "verify 缺少身分步驟：$token" }
}

$restore = $sources['restore-dahye-skin.ps1']
foreach ($token in @('SelfTest','touchesConfig = $false','Test-DahyeRecordedProcess','Archive-DahyeState','Wait-DahyePortClosed','shell:AppsFolder','OpenAI.Codex_2p2nqsd0c76g0!App')) {
  if (-not $restore.Contains($token)) { throw "restore 缺少復原步驟：$token" }
}

$all = ($sources.Values -join "`n")
foreach ($forbidden in @('appearanceTheme','Set-Content $Config','RestoreConfigBackup','CodexDreamSkin\state.json')) {
  if ($all.Contains($forbidden)) { throw "launcher 含禁用設定行為：$forbidden" }
}

Write-Host 'PASS launcher.tests.ps1'
