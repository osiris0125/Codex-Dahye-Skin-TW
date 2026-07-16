[CmdletBinding()]
param(
  [int]$Port = 9435,
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-DahyeOperationLock
$verifyExitCode = 1
try {
  $StatePath = Join-Path $env:LOCALAPPDATA 'CodexDahyeSkin\runtime\state.json'
  $state = Read-DahyeState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $state -and $state.port) { $Port = [int]$state.port }
  Assert-DahyePort -Port $Port
  $node = Get-DahyeNodeRuntime
  $currentCodex = Get-DahyeCodexInstall
  $codex = $currentCodex
  $cdpIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $codex
  if ($null -eq $cdpIdentity -and $null -ne $state) {
    $savedCodex = Get-DahyeCodexInstallFromState -State $state
    if ($null -ne $savedCodex -and
      -not (Test-DahyePathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable)) {
      $savedIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $cdpIdentity = $savedIdentity
      }
    }
  }
  if ($null -eq $cdpIdentity) {
    throw "本機回環連接埠 $Port 上沒有已驗證的 Codex CDP 端點。"
  }
  if ($null -ne $state -and $state.browserId -and "$($state.browserId)" -cne $cdpIdentity.BrowserId) {
    throw '目前的 CDP 瀏覽器與已儲存的李多慧繁體中文皮膚工作階段不符；狀態檔已保留。'
  }

  $arguments = @($injector, '--verify', '--port', "$Port", '--browser-id', $cdpIdentity.BrowserId,
    '--timeout-ms', '30000')
  if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
  & $node.Path @arguments
  $verifyExitCode = $LASTEXITCODE
} finally {
  Exit-DahyeOperationLock -Mutex $operationLock
}
exit $verifyExitCode
