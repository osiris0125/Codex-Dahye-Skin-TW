Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$files = Get-ChildItem -LiteralPath $windowsRoot -Recurse -File -Filter '*.ps1'
foreach ($file in $files) {
  $bytes = [IO.File]::ReadAllBytes($file.FullName)
  $hasNonAscii = @($bytes | Where-Object { $_ -ge 0x80 }).Count -gt 0
  if (-not $hasNonAscii) { continue }
  $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  if (-not $hasUtf8Bom) {
    throw "PowerShell 5.1 requires a UTF-8 BOM for non-ASCII source: $($file.FullName)"
  }
}

Write-Host 'PASS powershell-encoding.tests.ps1'
