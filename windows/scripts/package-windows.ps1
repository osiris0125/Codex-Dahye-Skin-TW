Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DahyeRelativePath {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
  $rootUri = New-Object Uri(([IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'))
  $pathUri = New-Object Uri([IO.Path]::GetFullPath($Path))
  [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Get-DahyePackageSourceFiles {
  param([Parameter(Mandatory)][string]$SourceRoot)
  $root = [IO.Path]::GetFullPath($SourceRoot)
  $fixed = @(
    'README.md','AGENTS.md','LICENSE','SECURITY.md',
    'docs\INSTALL_WITH_CODEX.md','docs\UPSTREAM_WINDOWS_PARITY.md','windows\CHANGELOG.md'
  )
  $files = @()
  foreach ($relative in $fixed) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "建置來源缺少：$relative" }
    $files += Get-Item -LiteralPath $path
  }
  foreach ($folder in @('windows\assets','windows\references','windows\scripts')) {
    $path = Join-Path $root $folder
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "建置來源缺少：$folder" }
    $files += Get-ChildItem -LiteralPath $path -Recurse -File |
      Where-Object { $_.FullName -ine (Join-Path $root 'windows\assets\dahye-hero.png') }
  }
  @($files | Sort-Object FullName -Unique)
}

function Resolve-DahyeHeroPng {
  param([Parameter(Mandatory)][string]$HeroPath)
  if (-not [IO.Path]::IsPathRooted($HeroPath)) { throw 'HeroPath 必須是 PNG 的絕對路徑。' }
  $resolved = (Resolve-Path -LiteralPath $HeroPath -ErrorAction Stop).Path
  $file = Get-Item -LiteralPath $resolved
  if ($file.Extension -ine '.png') { throw 'HeroPath 必須指向 PNG 檔案。' }
  if ($file.Length -lt 1024 -or $file.Length -gt 20MB) { throw '主視覺 PNG 必須介於 1 KB 與 20 MB。' }
  $bytes = [IO.File]::ReadAllBytes($resolved)
  $signature = @(0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)
  for ($index = 0; $index -lt $signature.Count; $index++) {
    if ($bytes[$index] -ne $signature[$index]) { throw 'HeroPath 不是有效的 PNG 檔頭。' }
  }
  return $resolved
}

function Write-DahyePackageJson {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}

function Test-DahyePackageManifest {
  param([Parameter(Mandatory)][string]$PackagePath)
  try {
    $root = (Resolve-Path -LiteralPath $PackagePath).Path
    if ((Split-Path $root -Leaf) -cne 'package-v1') { return $false }
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.packageName -cne 'package-v1') { return $false }
    $listed = @($manifest.files)
    foreach ($record in $listed) {
      if ([string]$record.path -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
      $file = Join-Path $root ([string]$record.path)
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
      if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne [string]$record.sha256) { return $false }
    }
    $actual = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object Name -ne 'package-manifest.json')
    return $actual.Count -eq $listed.Count
  } catch {
    return $false
  }
}

function Build-DahyePackage {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$HeroPath
  )
  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  $output = [IO.Path]::GetFullPath($OutputPath)
  $hero = Resolve-DahyeHeroPng -HeroPath $HeroPath
  if ((Split-Path $output -Leaf) -cne 'package-v1') { throw '建置輸出 leaf 必須是 package-v1。' }
  if ($output.Equals($source, [StringComparison]::OrdinalIgnoreCase)) { throw '建置輸出不可等於來源根目錄。' }
  $parent = Split-Path $output -Parent
  [IO.Directory]::CreateDirectory($parent) | Out-Null
  if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
  $stage = "$output.stage-$([guid]::NewGuid().ToString('N'))"
  [IO.Directory]::CreateDirectory($stage) | Out-Null
  try {
    $records = @()
    foreach ($file in @(Get-DahyePackageSourceFiles -SourceRoot $source)) {
      $relative = Get-DahyeRelativePath -Root $source -Path $file.FullName
      $destination = Join-Path $stage $relative
      [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
      Copy-Item -LiteralPath $file.FullName -Destination $destination
      $records += [pscustomobject]@{ path=$relative.Replace('\','/'); sha256=(Get-FileHash $destination -Algorithm SHA256).Hash }
    }
    $heroRelative = 'windows\assets\dahye-hero.png'
    $heroDestination = Join-Path $stage $heroRelative
    [IO.Directory]::CreateDirectory((Split-Path $heroDestination -Parent)) | Out-Null
    Copy-Item -LiteralPath $hero -Destination $heroDestination
    $records += [pscustomobject]@{
      path = $heroRelative.Replace('\','/')
      sha256 = (Get-FileHash $heroDestination -Algorithm SHA256).Hash
    }
    $sourceCommit = (& git -C $source rev-parse HEAD 2>$null | Select-Object -First 1)
    $manifest = [pscustomobject]@{
      schemaVersion = 1
      packageName = 'package-v1'
      sourceCommit = [string]$sourceCommit
      files = @($records | Sort-Object path)
    }
    Write-DahyePackageJson -Value $manifest -Path (Join-Path $stage 'package-manifest.json')
    Move-Item -LiteralPath $stage -Destination $output
    if (-not (Test-DahyePackageManifest -PackagePath $output)) { throw '建置後 manifest 驗證失敗。' }
    return $output
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Install-DahyePackageAtomic {
  param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$AllowedParent
  )
  $package = (Resolve-Path -LiteralPath $PackagePath).Path
  if (-not (Test-DahyePackageManifest -PackagePath $package)) { throw '來源 package manifest 驗證失敗。' }
  $parent = [IO.Path]::GetFullPath($AllowedParent).TrimEnd('\')
  $destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
  if ((Split-Path $destinationFull -Leaf) -cne 'package-v1') { throw '安裝目的 leaf 不合法。' }
  if ((Split-Path $destinationFull -Parent).TrimEnd('\') -cne $parent) { throw '安裝目的不在允許的 sibling 目錄。' }
  if ($destinationFull -match '(?i)WindowsApps') { throw '安裝目的指向受保護路徑。' }
  [IO.Directory]::CreateDirectory($parent) | Out-Null
  $stage = Join-Path $parent ('.package-v1.stage-' + [guid]::NewGuid().ToString('N'))
  $backup = $null
  try {
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $package -Force) {
      Copy-Item -LiteralPath $item.FullName -Destination $stage -Recurse -Force
    }
    $manifest = Get-Content -Raw (Join-Path $stage 'package-manifest.json') -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.packageName -cne 'package-v1') {
      throw 'stage package manifest 識別不符。'
    }
    foreach ($record in $manifest.files) {
      $file = Join-Path $stage ([string]$record.path)
      if (-not (Test-Path $file) -or (Get-FileHash $file -Algorithm SHA256).Hash -cne [string]$record.sha256) {
        throw 'stage package manifest 驗證失敗。'
      }
    }
    if (Test-Path -LiteralPath $destinationFull) {
      $backup = Join-Path $parent ("package-v1.backup-{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,6))
      Move-Item -LiteralPath $destinationFull -Destination $backup
    }
    Move-Item -LiteralPath $stage -Destination $destinationFull
    if (-not (Test-DahyePackageManifest -PackagePath $destinationFull)) { throw '安裝後 manifest 驗證失敗。' }
    return $destinationFull
  } catch {
    if (-not (Test-Path -LiteralPath $destinationFull) -and $backup -and (Test-Path -LiteralPath $backup)) {
      Move-Item -LiteralPath $backup -Destination $destinationFull
    }
    throw
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function New-DahyeShortcuts {
  param([Parameter(Mandatory)][string]$InstalledRoot, [Parameter(Mandatory)][string]$DesktopRoot)
  $shell = New-Object -ComObject WScript.Shell
  $definitions = @(
    [pscustomobject]@{ Name='Codex 李多慧繁中皮膚.lnk'; Script='apply-dahye-skin.ps1'; Extra=''; Description='以獨立 Windows worker 重啟並套用李多慧繁體中文皮膚' },
    [pscustomobject]@{ Name='恢復官方 Codex 外觀（李多慧皮膚）.lnk'; Script='restore-dahye-skin.ps1'; Extra=''; Description='移除李多慧皮膚工作階段並重開官方 Codex' }
  )
  $created = @()
  foreach ($definition in $definitions) {
    $path = Join-Path $DesktopRoot $definition.Name
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $scriptPath = Join-Path $InstalledRoot ("windows\scripts\{0}" -f $definition.Script)
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"$($definition.Extra)"
    $shortcut.WorkingDirectory = $InstalledRoot
    $shortcut.Description = $definition.Description
    $shortcut.Save()
    $created += $path
  }
  return $created
}
