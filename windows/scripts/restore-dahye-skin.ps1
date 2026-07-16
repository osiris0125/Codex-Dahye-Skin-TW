param(
  [switch]$NoRelaunch,
  [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'state-windows.ps1')
. (Join-Path $PSScriptRoot 'common-windows.ps1')

if ($SelfTest) {
  $parseErrors = @()
  foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    $parseErrors += @($errors)
  }
  if ($parseErrors.Count -gt 0) { throw "復原腳本語法檢查失敗：$($parseErrors[0].Message)" }
  $package = Get-RegisteredCodexPackage
  $nodePath = Get-DahyeNodePath -MinimumMajor 22
  [pscustomobject]@{
    pass = $true
    officialPackageFound = $true
    packageFullName = $package.PackageFullName
    nodeAvailable = $true
    nodePath = $nodePath
    touchesConfig = $false
  } | ConvertTo-Json -Compress
  return
}

$mutex = $null
$statePath = Join-Path (Get-DahyeStateRoot) 'state.json'
try {
  $mutex = Enter-DahyeOperationLock
  $state = Read-DahyeState -StatePath $statePath
  if ($null -eq $state) {
    Write-Host '目前沒有執行中的李多慧皮膚工作階段。'
    if (-not $NoRelaunch) { Start-Process explorer.exe 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App' }
    return
  }
  $package = Get-RegisteredCodexPackage
  if ($package.PackageFullName -ine $state.codexPackageFullName -or -not (Test-DahyePathEqual -Left $package.PackageRoot -Right $state.codexPackageRoot)) {
    throw '目前註冊的 Codex Store 套件與 Dahye state 不符，安全停止。'
  }
  if (Test-DahyeRecordedProcess -State $state) {
    Stop-Process -Id ([int]$state.injectorPid) -Force -ErrorAction Stop
  }
  Stop-DahyeVerifiedCodexProcesses -Package $package -Port ([int]$state.port)
  Archive-DahyeState -StatePath $statePath -Reason 'restored' | Out-Null
  Wait-DahyePortClosed -Port ([int]$state.port) -TimeoutSeconds 15 | Out-Null
  if (-not $NoRelaunch) {
    Start-Process explorer.exe 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
  }
  Write-Host '已移除李多慧皮膚工作階段，官方 Codex 外觀已復原。'
} finally {
  Exit-DahyeOperationLock -Mutex $mutex
}
