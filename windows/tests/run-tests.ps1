Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -File |
  Where-Object { $_.Name -match '\.tests\.(ps1|mjs)$' } |
  Sort-Object Name)
foreach ($test in $tests) {
  Write-Host "執行 $($test.Name)"
  if ($test.Extension -eq '.ps1') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test.FullName
  } else {
    & node $test.FullName
  }
  if ($LASTEXITCODE -ne 0) { throw "測試失敗：$($test.Name)" }
}
Write-Host "全部自動測試通過（$($tests.Count) 個測試檔）。"
