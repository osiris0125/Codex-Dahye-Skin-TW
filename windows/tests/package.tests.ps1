Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\scripts\package-windows.ps1')

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temp = Join-Path $env:TEMP ("dahye-package-test-" + [guid]::NewGuid().ToString('N'))
$output = Join-Path $temp 'build\package-v1'
$installParent = Join-Path $temp 'installed'
$destination = Join-Path $installParent 'package-v1'
$pinned = Join-Path $installParent 'package-legacy'
$hero = Join-Path $temp 'authorized-hero.png'
New-Item -ItemType Directory -Path $pinned -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $pinned 'DO-NOT-TOUCH.bin'), 'protected', [Text.UTF8Encoding]::new($false))
$pinnedHash = (Get-FileHash (Join-Path $pinned 'DO-NOT-TOUCH.bin') -Algorithm SHA256).Hash
$png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
$padded = New-Object byte[] 1024
[Array]::Copy($png, $padded, $png.Length)
[IO.File]::WriteAllBytes($hero, $padded)

try {
  Build-DahyePackage -SourceRoot $repo -OutputPath $output -HeroPath $hero | Out-Null
  if (-not (Test-DahyePackageManifest -PackagePath $output)) { throw '初次 build manifest 失敗。' }
  if (-not (Test-Path -LiteralPath (Join-Path $output 'windows\assets\dahye-hero.png'))) { throw '建置未納入使用者提供的圖片。' }
  if (Test-Path -LiteralPath (Join-Path $repo 'windows\assets\dahye-hero.png')) { throw '建置不得把圖片寫回來源 repo。' }
  & node (Join-Path $output 'windows\scripts\injector.mjs') --check-payload
  if ($LASTEXITCODE -ne 0) { throw '建置後 payload 驗證失敗。' }
  Add-Content -LiteralPath (Join-Path $output 'README.md') -Value 'tampered'
  if (Test-DahyePackageManifest -PackagePath $output) { throw '遭竄改 package 未被拒絕。' }
  Build-DahyePackage -SourceRoot $repo -OutputPath $output -HeroPath $hero | Out-Null

  $badHero = Join-Path $temp 'bad.png'
  [IO.File]::WriteAllBytes($badHero, (New-Object byte[] 1024))
  $badRejected = $false
  try { Resolve-DahyeHeroPng -HeroPath $badHero | Out-Null } catch { $badRejected = $true }
  if (-not $badRejected) { throw '錯誤 PNG 檔頭未被拒絕。' }

  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $destination 'old.txt') -Value 'old Dahye package'
  Install-DahyePackageAtomic -PackagePath $output -Destination $destination -AllowedParent $installParent | Out-Null
  if (-not (Test-DahyePackageManifest -PackagePath $destination)) { throw '安裝後 manifest 失敗。' }
  if ((Get-FileHash (Join-Path $pinned 'DO-NOT-TOUCH.bin') -Algorithm SHA256).Hash -cne $pinnedHash) { throw '舊 pinned package 被修改。' }
  if (@(Get-ChildItem $installParent -Directory -Filter 'package-v1.backup-*').Count -ne 1) { throw '既有 Dahye package 未封存。' }

  $rejected = $false
  try { Install-DahyePackageAtomic -PackagePath $output -Destination (Join-Path $installParent 'wrong-name') -AllowedParent $installParent } catch { $rejected = $true }
  if (-not $rejected) { throw '錯誤 destination leaf 未被拒絕。' }
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS package.tests.ps1'
