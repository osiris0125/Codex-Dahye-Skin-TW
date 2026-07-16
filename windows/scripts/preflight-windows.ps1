Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-RegisteredCodexPackage -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'common-windows.ps1')
}
if (-not (Get-Command Write-DahyeJsonAtomic -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'state-windows.ps1')
}

function Get-DahyeRecoveryToolRecords {
  param([Parameter(Mandatory)][string]$PackageRoot)
  $root = (Resolve-Path -LiteralPath $PackageRoot).Path
  $relativePaths = @(
    'windows\scripts\restore-dahye-skin.ps1',
    'windows\scripts\start-dahye-skin.ps1',
    'windows\scripts\injector.mjs',
    'windows\scripts\preflight-windows.ps1',
    'windows\scripts\package-windows.ps1'
  )
  if (Test-Path -LiteralPath (Join-Path $root 'package-manifest.json')) {
    $relativePaths += 'package-manifest.json'
  }
  foreach ($relative in $relativePaths) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "復原基線缺少：$relative" }
    [pscustomobject]@{
      path = $relative.Replace('\','/')
      sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
  }
}

function Invoke-DahyeRestoreSelfTest {
  param([Parameter(Mandatory)][string]$RestorePath)
  $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RestorePath -SelfTest 2>&1
  if ($LASTEXITCODE -ne 0) { throw "復原 SelfTest 失敗：$($output -join ' ')" }
  return $true
}

function Invoke-DahyePublicPreflight {
  param(
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][string]$StateRoot,
    [switch]$Persist,
    [scriptblock]$PackageProvider = { Get-RegisteredCodexPackage },
    [scriptblock]$NodeProvider = { Get-DahyeNodePath -MinimumMajor 22 },
    [scriptblock]$RestoreSelfTest = { param($path) Invoke-DahyeRestoreSelfTest -RestorePath $path }
  )
  $root = (Resolve-Path -LiteralPath $PackageRoot).Path
  $package = & $PackageProvider
  if ($null -eq $package -or -not $package.PackageRoot -or -not $package.PackageFullName -or -not $package.PackageFamilyName) {
    throw '官方 Codex 套件驗證資料不完整。'
  }
  $nodePath = & $NodeProvider
  if ([string]::IsNullOrWhiteSpace([string]$nodePath)) { throw 'Node.js 驗證失敗。' }
  $restorePath = Join-Path $root 'windows\scripts\restore-dahye-skin.ps1'
  if (-not (& $RestoreSelfTest $restorePath)) { throw '復原 SelfTest 未通過。' }

  $baseline = [pscustomobject]@{
    schemaVersion = 1
    createdAt = [DateTime]::UtcNow.ToString('o')
    skinPackageRoot = $root
    officialCodex = [pscustomobject]@{
      packageRoot = [string]$package.PackageRoot
      packageFullName = [string]$package.PackageFullName
      packageFamilyName = [string]$package.PackageFamilyName
    }
    nodePath = [string]$nodePath
    recoveryTools = @(Get-DahyeRecoveryToolRecords -PackageRoot $root)
    touchesOfficialConfig = $false
  }
  if ($Persist) {
    $baselinePath = Join-Path ([IO.Path]::GetFullPath($StateRoot)) 'recovery-baseline.json'
    Write-DahyeJsonAtomic -Value $baseline -Path $baselinePath
  }
  return $baseline
}

function Assert-DahyeRecoveryBaselineCurrent {
  param(
    [Parameter(Mandatory)][string]$BaselinePath,
    [scriptblock]$PackageProvider = { Get-RegisteredCodexPackage },
    [scriptblock]$NodeProvider = { Get-DahyeNodePath -MinimumMajor 22 }
  )
  if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) { throw '找不到已驗證的復原基線，請重新執行安裝。' }
  $baseline = Get-Content -Raw -LiteralPath $BaselinePath -Encoding UTF8 | ConvertFrom-Json
  if ([int]$baseline.schemaVersion -ne 1 -or [bool]$baseline.touchesOfficialConfig) { throw '復原基線格式不合法。' }
  $package = & $PackageProvider
  if ([string]$package.PackageFullName -cne [string]$baseline.officialCodex.packageFullName -or
      [string]$package.PackageFamilyName -cne [string]$baseline.officialCodex.packageFamilyName -or
      -not (Test-DahyePathEqual -Left ([string]$package.PackageRoot) -Right ([string]$baseline.officialCodex.packageRoot))) {
    throw '官方 Codex 套件已變更，請重新執行安裝以更新復原基線。'
  }
  $nodePath = & $NodeProvider
  if (-not (Test-DahyePathEqual -Left ([string]$nodePath) -Right ([string]$baseline.nodePath))) {
    throw 'Node.js 路徑已變更，請重新執行安裝。'
  }
  $root = [string]$baseline.skinPackageRoot
  foreach ($record in @($baseline.recoveryTools)) {
    $relative = ([string]$record.path).Replace('/','\')
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)') { throw '復原基線包含不安全路徑。' }
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$record.sha256) {
      throw "復原工具已變更：$relative"
    }
  }
  return $true
}
