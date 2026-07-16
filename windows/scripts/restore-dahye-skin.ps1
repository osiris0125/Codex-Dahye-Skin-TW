[CmdletBinding()]
param(
  [int]$Port = 9435,
  [switch]$Uninstall,
  [switch]$PromptRestart,
  [switch]$ForceRestart,
  [switch]$NoRelaunch,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
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
  $package = Get-DahyeCodexInstall
  $node = Get-DahyeNodeRuntime -MinimumMajor 22
  [pscustomobject]@{
    pass = $true
    officialPackageFound = $true
    packageFullName = $package.PackageFullName
    nodeAvailable = $true
    nodePath = $node.Path
    touchesConfig = $false
  } | ConvertTo-Json -Compress
  return
}

$operationLock = Enter-DahyeOperationLock
try {
  Assert-DahyePort -Port $Port

  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDahyeSkin\runtime'
  $StatePath = Join-Path $StateRoot 'state.json'
  $state = Read-DahyeState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $state -and $state.port) {
    $Port = [int]$state.port
    Assert-DahyePort -Port $Port
  }

  $currentCodex = $null
  try { $currentCodex = Get-DahyeCodexInstall } catch { Write-Warning $_.Exception.Message }
  $savedPathCandidate = Get-DahyeCodexStatePathCandidate -State $state
  $savedCodex = Get-DahyeCodexInstallFromState -State $state
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and $null -ne $currentCodex -and
    (Test-DahyePathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-DahyePathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = @(Get-DahyeCodexProcesses -Codex $savedPathCandidate).Count -gt 0
    $unverifiedSavedOwnsPort = Test-DahyeCodexPortOwner -Port $Port -Codex $savedPathCandidate
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw '已儲存的 Codex 路徑仍在執行，但已無法對應已註冊的 OpenAI.Codex 套件。請手動關閉；狀態檔已保留。'
    }
  }
  $savedIsDifferent = [bool]($null -ne $savedCodex -and $null -ne $currentCodex -and
    -not (Test-DahyePathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  $currentRunning = $null -ne $currentCodex -and @(Get-DahyeCodexProcesses -Codex $currentCodex).Count -gt 0
  $savedRunning = $null -ne $savedCodex -and @(Get-DahyeCodexProcesses -Codex $savedCodex).Count -gt 0
  $savedOwnsPort = $null -ne $savedCodex -and (Test-DahyeCodexPortOwner -Port $Port -Codex $savedCodex)
  if ($savedIsDifferent -and $currentRunning -and ($savedRunning -or $savedOwnsPort)) {
    throw '同時偵測到多個 Codex 套件版本。請先手動關閉再復原；狀態檔已保留。'
  }

  $codex = $currentCodex
  if ($savedRunning -or $savedOwnsPort -or $null -eq $currentCodex) {
    $codex = $savedCodex
    if ($null -ne $codex -and $savedIsDifferent) {
      Write-Warning '正在使用已儲存並重新驗證的 Codex 套件身分，關閉舊版 CDP 工作階段。'
    } elseif ($null -ne $codex -and $null -eq $currentCodex) {
      Write-Warning '目前找不到新版套件，正在使用已向 Store 註冊資訊重新驗證的 Codex 身分。'
    }
  }
  $relaunchCodex = if ($null -ne $currentCodex) { $currentCodex } else { $codex }
  $codexRunning = $null -ne $codex -and @(Get-DahyeCodexProcesses -Codex $codex).Count -gt 0
  $portOwnedByCodex = $null -ne $codex -and (Test-DahyeCodexPortOwner -Port $Port -Codex $codex)
  if ($portOwnedByCodex -and -not $codexRunning) {
    throw '找到 Codex 擁有的監聽連接埠，但找不到可安全管理的 Codex 程序；狀態檔已保留。'
  }
  if ($null -ne $state -and $null -eq $codex -and -not (Test-DahyePortAvailable -Port $Port)) {
    throw "連接埠 $Port 仍在使用，但無法驗證是否由 Codex 擁有；狀態檔已保留。"
  }

  $shouldCloseCodex = $codexRunning
  $forceAuthorized = [bool]$ForceRestart
  if ($shouldCloseCodex -and $PromptRestart) {
    $restartMessage = if ($NoRelaunch) {
      '復原程序將關閉 Codex，並移除李多慧繁體中文皮膚與其 CDP 工作階段。要繼續嗎？'
    } else {
      '復原程序將關閉 Codex、移除李多慧繁體中文皮膚與其 CDP 工作階段，再重新開啟官方 Codex。要繼續嗎？'
    }
    $forceAuthorized = Confirm-DahyeRestart -Message $restartMessage
    if (-not $forceAuthorized) {
      Write-Host '已取消復原；狀態檔與 Codex 均未變更。'
      exit 0
    }
  }

  $restoreError = $null
  try {
    if ($shouldCloseCodex) {
      Stop-DahyeCodex -Codex $codex -AllowForce:$forceAuthorized
      if ($portOwnedByCodex -and -not (Wait-DahyePortAvailable -Port $Port -TimeoutSeconds 5)) {
        throw "Codex 關閉後，連接埠 $Port 仍在監聽；狀態檔已保留供檢查。"
      }
    }

    $recordedInjectorStopped = Stop-DahyeRecordedInjector -State $state
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-DahyeStateFile -Path $StatePath
      Write-Warning "無法確認舊注入程序身分，已將狀態檔封存於：$staleStatePath"
    }

    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    if ($Uninstall) {
      $desktop = [Environment]::GetFolderPath('Desktop')
      $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
      @(
        (Join-Path $desktop 'Codex 李多慧繁體中文皮膚.lnk'),
        (Join-Path $desktop 'Codex 李多慧繁體中文皮膚 - Restore.lnk'),
        (Join-Path $startMenu 'Codex 李多慧繁體中文皮膚.lnk')
      ) | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
    }

    if ($shouldCloseCodex -and -not $NoRelaunch) {
      if ($null -eq $relaunchCodex -or -not (Test-Path -LiteralPath $relaunchCodex.Executable)) {
        throw '找不到目前 Codex 的執行檔，無法自動重新開啟。'
      }
      Start-Process -FilePath $relaunchCodex.Executable | Out-Null
    }
  } catch {
    $restoreError = $_
    if ($shouldCloseCodex -and -not $NoRelaunch -and $null -ne $relaunchCodex -and
      @(Get-DahyeCodexProcesses -Codex $codex).Count -eq 0 -and (Test-Path -LiteralPath $relaunchCodex.Executable)) {
      try { Start-Process -FilePath $relaunchCodex.Executable | Out-Null } catch {
        Write-Warning '復原失敗，而且無法自動重新開啟 Codex。'
      }
    }
    throw $restoreError
  }

  Write-Host '李多慧繁體中文皮膚已復原；已儲存的 CDP 工作階段已關閉。'
} finally {
  Exit-DahyeOperationLock -Mutex $operationLock
}
