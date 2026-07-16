Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\scripts\common-windows.ps1')
. (Join-Path $PSScriptRoot '..\scripts\state-windows.ps1')
. (Join-Path $PSScriptRoot '..\scripts\preflight-windows.ps1')

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temp = Join-Path $env:TEMP ('dahye-preflight-test-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $temp 'package-v1'
$stateRoot = Join-Path $temp 'runtime'
$scriptRoot = Join-Path $fixture 'windows\scripts'
[IO.Directory]::CreateDirectory($scriptRoot) | Out-Null
foreach ($name in @(
  'restore-dahye-skin.ps1','start-dahye-skin.ps1','injector.mjs','preflight-windows.ps1',
  'package-windows.ps1','common-windows.ps1','io-windows.ps1','state-windows.ps1'
)) {
  Copy-Item -LiteralPath (Join-Path $repo "windows\scripts\$name") -Destination (Join-Path $scriptRoot $name)
}

$fakePackage = [pscustomobject]@{
  Executable = 'C:\Store\app\ChatGPT.exe'
  PackageRoot = 'C:\Store'
  PackageFullName = 'OpenAI.Codex_1.0.0.0_x64__2p2nqsd0c76g0'
  PackageFamilyName = 'OpenAI.Codex_2p2nqsd0c76g0'
}
$packageProvider = { $fakePackage }.GetNewClosure()
$nodeProvider = { 'C:\Tools\node.exe' }
$selfTest = { param($path) Test-Path -LiteralPath $path }

try {
  Invoke-DahyePublicPreflight -PackageRoot $fixture -StateRoot $stateRoot -Persist `
    -PackageProvider $packageProvider -NodeProvider $nodeProvider -RestoreSelfTest $selfTest | Out-Null
  $baselinePath = Join-Path $stateRoot 'recovery-baseline.json'
  if (-not (Test-Path -LiteralPath $baselinePath)) { throw 'preflight 未保存復原基線。' }
  $baseline = Get-Content -Raw -LiteralPath $baselinePath -Encoding UTF8 | ConvertFrom-Json
  $recordedPaths = @($baseline.recoveryTools | ForEach-Object { [string]$_.path })
  foreach ($required in @(
    'windows/scripts/common-windows.ps1',
    'windows/scripts/io-windows.ps1',
    'windows/scripts/state-windows.ps1'
  )) {
    if ($recordedPaths -notcontains $required) { throw "復原基線未保護相依檔：$required" }
  }
  Assert-DahyeRecoveryBaselineCurrent -BaselinePath $baselinePath `
    -PackageProvider $packageProvider -NodeProvider $nodeProvider | Out-Null

  Add-Content -LiteralPath (Join-Path $scriptRoot 'injector.mjs') -Value '// tampered'
  $tamperRejected = $false
  try {
    Assert-DahyeRecoveryBaselineCurrent -BaselinePath $baselinePath `
      -PackageProvider $packageProvider -NodeProvider $nodeProvider | Out-Null
  } catch { $tamperRejected = $true }
  if (-not $tamperRejected) { throw '復原工具遭竄改後未被基線拒絕。' }

  $incompleteRejected = $false
  try {
    Invoke-DahyePublicPreflight -PackageRoot $fixture -StateRoot $stateRoot `
      -PackageProvider { [pscustomobject]@{ PackageRoot='C:\Store' } } `
      -NodeProvider $nodeProvider -RestoreSelfTest $selfTest | Out-Null
  } catch { $incompleteRejected = $true }
  if (-not $incompleteRejected) { throw '不完整官方套件資料未被拒絕。' }
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS preflight.tests.ps1'
