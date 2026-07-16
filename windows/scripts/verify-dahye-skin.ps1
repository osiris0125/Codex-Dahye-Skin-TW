param([string]$ScreenshotPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'state-windows.ps1')
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$statePath = Join-Path (Get-DahyeStateRoot) 'state.json'
$state = Read-DahyeState -StatePath $statePath
if ($null -eq $state) { throw '找不到執行中的李多慧皮膚 state。' }
if (-not (Test-DahyeRecordedProcess -State $state)) { throw '李多慧 injector 程序身分與 state 不符。' }
$package = Get-RegisteredCodexPackage
if ($package.PackageFullName -ine $state.codexPackageFullName -or -not (Test-DahyePathEqual -Left $package.PackageRoot -Right $state.codexPackageRoot)) {
  throw '目前註冊的 Codex Store 套件與 state 不符。'
}

$arguments = @($state.injectorPath, '--verify', '--port', "$($state.port)", '--browser-id', $state.browserId)
if ($ScreenshotPath) {
  $arguments += @('--screenshot', [IO.Path]::GetFullPath($ScreenshotPath))
}
& $state.nodePath @arguments
if ($LASTEXITCODE -ne 0) { throw '李多慧皮膚驗證失敗。' }
