param(
  [Parameter(Mandatory)][string]$HeroPath,
  [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'package-windows.ps1')

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutputPath) { $OutputPath = Join-Path $sourceRoot 'dist\package-v1' }
$result = Build-DahyePackage -SourceRoot $sourceRoot -OutputPath $OutputPath -HeroPath $HeroPath
Write-Host "已建立可安裝 package：$result"
