[CmdletBinding()]
param(
  [int]$Port = 9435,
  [Alias('RestartCodex')][switch]$RestartExisting,
  [Alias('PromptForRestart')][switch]$PromptRestart,
  [string]$ProfilePath,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'state-windows.ps1')
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'preflight-windows.ps1')

$operationLock = Enter-DahyeOperationLock
try {
  Assert-NoLegacySkinSession
  Assert-DahyePort -Port $Port
  if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
  $node = Get-DahyeNodeRuntime
  $currentCodex = Get-DahyeCodexInstall
  $codex = $currentCodex
  $StateRoot = Get-DahyeStateRoot
  $BaselinePath = Join-Path $StateRoot 'recovery-baseline.json'
  Assert-DahyeRecoveryBaselineCurrent -BaselinePath $BaselinePath
  $StatePath = Join-Path $StateRoot 'state.json'
  $StdoutPath = Join-Path $StateRoot 'injector.log'
  $StderrPath = Join-Path $StateRoot 'injector-error.log'
  $VerifyPath = Join-Path $StateRoot 'verify.log'
  New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

  $previousState = Read-DahyeState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $previousState -and $previousState.port) {
    $savedPort = [int]$previousState.port
    Assert-DahyePort -Port $savedPort
    $Port = $savedPort
  }
  $savedPathCandidate = Get-DahyeCodexStatePathCandidate -State $previousState
  $savedCodex = Get-DahyeCodexInstallFromState -State $previousState
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and
    (Test-DahyePathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-DahyePathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = @(Get-DahyeCodexProcesses -Codex $savedPathCandidate).Count -gt 0
    $unverifiedSavedOwnsPort = Test-DahyeCodexPortOwner -Port $Port -Codex $savedPathCandidate
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw '已儲存的 Codex 路徑仍在執行，但已無法對應已註冊的 OpenAI.Codex 套件。請手動關閉；狀態檔已保留。'
    }
  }

  $currentProcesses = @(Get-DahyeCodexProcesses -Codex $currentCodex)
  $codexToStop = $currentCodex
  $cdpIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $currentCodex
  $savedIsDifferent = [bool]($null -ne $savedCodex -and
    -not (Test-DahyePathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  if ($savedIsDifferent) {
    $savedProcesses = @(Get-DahyeCodexProcesses -Codex $savedCodex)
    $savedOwnsPort = Test-DahyeCodexPortOwner -Port $Port -Codex $savedCodex
    if ($currentProcesses.Count -gt 0 -and ($savedProcesses.Count -gt 0 -or $savedOwnsPort)) {
      throw '同時偵測到多個已註冊的 Codex 套件版本。請先手動關閉，再啟動李多慧繁體中文皮膚。'
    }
    if ($savedProcesses.Count -gt 0 -or $savedOwnsPort) {
      if ($savedOwnsPort -and $savedProcesses.Count -eq 0) {
        throw '已儲存的 Codex 監聽連接埠仍在使用，但無法安全管理其程序；狀態檔已保留。'
      }
      $savedIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $codexToStop = $savedCodex
        $cdpIdentity = $savedIdentity
        Write-Warning '正在對仍執行中的已註冊 Codex 版本重新套用李多慧繁體中文皮膚；該程式退出後會改用目前的 Store 版本。'
      } else {
        $codexToStop = $savedCodex
        $currentProcesses = $savedProcesses
      }
    }
  }
  $debugReady = $null -ne $cdpIdentity
  $codexProcesses = if (Test-DahyePathEqual -Left $codexToStop.Executable -Right $currentCodex.Executable) {
    $currentProcesses
  } else {
    @(Get-DahyeCodexProcesses -Codex $codexToStop)
  }
  $closedExistingCodex = $false
  if (-not $debugReady -and $codexProcesses.Count -gt 0) {
    $restartAuthorized = [bool]$RestartExisting
    if (-not $restartAuthorized -and $PromptRestart) {
      $restartAuthorized = Confirm-DahyeRestart -Message 'Codex 必須重新啟動一次才能套用李多慧繁體中文皮膚；尚未送出的輸入可能遺失。現在重新啟動嗎？'
      if (-not $restartAuthorized) {
        Write-Host '已取消啟動李多慧繁體中文皮膚；Codex 未被變更。'
        exit 0
      }
    }
    if (-not $restartAuthorized) {
      throw 'Codex 正在執行，但沒有已驗證的李多慧繁體中文皮膚 CDP 端點。請先關閉，或明確使用 -RestartExisting。'
    }
    Stop-DahyeCodex -Codex $codexToStop -AllowForce
    $closedExistingCodex = $true
    $codex = $currentCodex
  }

  $launchedWithCdp = $false
  try {
    if ($null -eq (Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $codex)) {
      if (-not (Test-DahyePortAvailable -Port $Port)) {
        if ($PortExplicit) { throw "連接埠 $Port 已被未驗證的監聽程序占用，請改用其他連接埠。" }
        $Port = Select-DahyePort -PreferredPort $Port
      }
      $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
      if ($ProfilePath) {
        New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
        $arguments += ConvertTo-DahyeProcessArgument -Value "--user-data-dir=$ProfilePath"
      }
      Start-Process -FilePath $codex.Executable -ArgumentList $arguments | Out-Null
      $launchedWithCdp = $true
    }

    $deadline = (Get-Date).AddSeconds(45)
    $cdpIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $codex
    while ($null -eq $cdpIdentity) {
      if ((Get-Date) -ge $deadline) {
        throw "Codex 未在 45 秒內於連接埠 $Port 提供已驗證的本機回環 CDP 端點。"
      }
      Start-Sleep -Milliseconds 400
      $cdpIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $codex
    }
  } catch {
    $launchError = $_
    if ($launchedWithCdp) {
      try { Stop-DahyeCodex -Codex $codex -AllowForce } catch {
        Write-Warning '啟動回滾無法完整關閉失敗的 CDP 工作階段。'
      }
    }
    if (($closedExistingCodex -or $launchedWithCdp) -and
      @(Get-DahyeCodexProcesses -Codex $codex).Count -eq 0) {
      if ($launchedWithCdp) {
        Write-Warning '李多慧繁體中文皮膚啟動失敗；正在不啟用偵錯連接埠的情況下重新開啟 Codex。'
      }
      try { Start-Process -FilePath $codex.Executable | Out-Null } catch {
        Write-Warning '啟動回滾無法自動重新開啟 Codex。'
      }
    }
    throw $launchError
  }

  try {
    $recordedInjectorStopped = Stop-DahyeRecordedInjector -State $previousState
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-DahyeStateFile -Path $StatePath
      Write-Warning "已封存過期的李多慧繁體中文皮膚狀態檔：$staleStatePath"
    }
  } catch {
    if ($launchedWithCdp) {
      try {
        Stop-DahyeCodex -Codex $codex -AllowForce
        Start-Process -FilePath $codex.Executable | Out-Null
      } catch {
        Write-Warning '狀態驗證回滾無法完整重啟 Codex；請關閉 Codex，確保其 CDP 連接埠已關閉。'
      }
    }
    throw
  }

  if ($ForegroundInjector) {
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    Exit-DahyeOperationLock -Mutex $operationLock
    $operationLock = $null
    & $node.Path $Injector --watch --port $Port --browser-id $cdpIdentity.BrowserId
    exit $LASTEXITCODE
  }

  $state = $null
  $daemon = $null
  try {
    $injectorArgs = @((ConvertTo-DahyeProcessArgument -Value $Injector), '--watch', '--port', "$Port",
      '--browser-id', $cdpIdentity.BrowserId)
    $daemon = Start-Process -FilePath $node.Path -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    Start-Sleep -Milliseconds 500
    if ($daemon.HasExited) { throw "注入程序在啟動期間已退出，請查看：$StderrPath" }

    $injectorStartedAt = Get-DahyeProcessStartedAt -ProcessId $daemon.Id
    if (-not $injectorStartedAt) { throw '無法安全記錄注入程序身分。' }
    $state = [pscustomobject]@{
      schemaVersion = 3
      platform = 'windows'
      port = $Port
      injectorPid = $daemon.Id
      injectorStartedAt = $injectorStartedAt
      injectorPath = $Injector
      nodePath = $node.Path
      nodeVersion = $node.Version
      codexExe = $codex.Executable
      codexPackageRoot = $codex.PackageRoot
      codexPackageFullName = $codex.PackageFullName
      codexPackageFamilyName = $codex.PackageFamilyName
      codexVersion = $codex.Version
      browserId = $cdpIdentity.BrowserId
      profilePath = $ProfilePath
      createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-DahyeState -Path $StatePath -State $state

    $verifyOutput = @(& $node.Path $Injector --verify --port $Port --browser-id $cdpIdentity.BrowserId `
      --timeout-ms 30000 2>&1)
    $verifyExitCode = $LASTEXITCODE
    Write-DahyeUtf8FileAtomically -Path $VerifyPath -Content (($verifyOutput -join "`r`n") + "`r`n")
    if ($verifyExitCode -ne 0) { throw "李多慧繁體中文皮膚驗證失敗，請查看：$VerifyPath" }
  } catch {
    $startupError = $_
    $injectorStopped = $true
    if ($null -ne $state) {
      try {
        $injectorStopped = Stop-DahyeRecordedInjector -State $state
      } catch {
        $injectorStopped = $false
        Write-Warning $_.Exception.Message
      }
    } elseif ($null -ne $daemon -and -not $daemon.HasExited) {
      try {
        Stop-Process -InputObject $daemon -Force -ErrorAction Stop
        [void]$daemon.WaitForExit(5000)
        $injectorStopped = $daemon.HasExited
      } catch {
        $injectorStopped = $false
        Write-Warning '啟動回滾期間無法停止新建立的注入程序。'
      }
    }
    if ($injectorStopped -and -not $launchedWithCdp) {
      try {
        $rollbackIdentity = Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $codex
        if ($null -ne $rollbackIdentity -and $rollbackIdentity.BrowserId -ceq $cdpIdentity.BrowserId) {
          & $node.Path $Injector --remove --port $Port --browser-id $cdpIdentity.BrowserId `
            --timeout-ms 5000 *> $null
          if ($LASTEXITCODE -ne 0) { throw '移除注入內容時回傳失敗狀態。' }
        }
      } catch {
        Write-Warning '啟動回滾無法移除部分套用中的即時皮膚；請重新載入或關閉 Codex 以清除。'
      }
    }
    if ($injectorStopped) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
    if ($launchedWithCdp) {
      try {
        Stop-DahyeCodex -Codex $codex -AllowForce
        Start-Process -FilePath $codex.Executable | Out-Null
      } catch {
        Write-Warning '啟動回滾無法完整重啟 Codex；請關閉 Codex，確保其 CDP 連接埠已關閉。'
      }
    }
    throw $startupError
  }

  Write-Host "Codex 李多慧繁體中文皮膚已啟用，並通過本機回環連接埠 $Port 的驗證。"
} finally {
  if ($null -ne $operationLock) { Exit-DahyeOperationLock -Mutex $operationLock }
}
