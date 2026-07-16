param([Parameter(Mandatory)][string]$HeroPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'state-windows.ps1')
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'preflight-windows.ps1')
. (Join-Path $PSScriptRoot 'package-windows.ps1')

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$desktop = [Environment]::GetFolderPath('Desktop')
$stateRoot = Get-DahyeStateRoot
$allowedParent = Join-Path $env:LOCALAPPDATA 'CodexDahyeSkin'
$destination = Join-Path $allowedParent 'package-v1'
$buildPath = Join-Path $sourceRoot 'dist\package-v1'

Resolve-DahyeHeroPng -HeroPath $HeroPath | Out-Null
Invoke-DahyePublicPreflight -PackageRoot $sourceRoot -StateRoot $stateRoot -Persist:$false | Out-Null
Build-DahyePackage -SourceRoot $sourceRoot -OutputPath $buildPath -HeroPath $HeroPath | Out-Null
if (-not (Test-DahyePackageManifest -PackagePath $buildPath)) { throw '安裝 package manifest 驗證失敗。' }
$installed = Install-DahyePackageAtomic -PackagePath $buildPath -Destination $destination -AllowedParent $allowedParent
Invoke-DahyePublicPreflight -PackageRoot $installed -StateRoot $stateRoot -Persist | Out-Null
New-DahyeShortcuts -InstalledRoot $installed -DesktopRoot $desktop | ForEach-Object { Write-Host "已建立捷徑：$_" }
Write-Host '李多慧繁體中文 Codex 皮膚已安裝；尚未啟動或重啟 Codex。'
