Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot '..\scripts\restore-dahye-skin.ps1'
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw "restore PowerShell 語法錯誤：$($errors[0].Message)" }

$source = Get-Content -Raw -LiteralPath $path
foreach ($required in @(
  'SelfTest',
  'touchesConfig = $false',
  'Stop-DahyeCodex',
  'Test-DahyeCodexPortOwner',
  'Stop-DahyeRecordedInjector',
  'Archive-DahyeStateFile',
  'Wait-DahyePortAvailable',
  'Get-DahyeCodexInstallFromState',
  'Start-Process -FilePath $relaunchCodex.Executable'
)) {
  if (-not $source.Contains($required)) { throw "restore 缺少上游安全步驟：$required" }
}

foreach ($forbidden in @('config.toml', 'appearanceTheme', 'Set-DahyeBaseTheme', 'Restore-DahyeConfig')) {
  if ($source.Contains($forbidden)) { throw "restore 不得碰觸官方設定：$forbidden" }
}

Write-Host 'PASS restore-parity.tests.ps1'
