[CmdletBinding()]
param(
  [ValidateRange(1024, 65535)][int]$Port = 9435,
  [switch]$DetachedWorker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'state-windows.ps1')
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'preflight-windows.ps1')
. (Join-Path $PSScriptRoot 'handoff-windows.ps1')

$stateRoot = Get-DahyeStateRoot
$baselinePath = Join-Path $stateRoot 'recovery-baseline.json'
$resultPath = Join-Path $stateRoot 'apply-result.json'
$dispatchPath = Join-Path $stateRoot 'apply-dispatch.json'
$logPath = Join-Path $stateRoot 'apply.log'
$errorLogPath = Join-Path $stateRoot 'apply-error.log'
$startPath = Join-Path $PSScriptRoot 'start-dahye-skin.ps1'

function Write-DahyeApplyLog {
  param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Content)
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

if ($DetachedWorker) {
  [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
  $startedAt = [DateTime]::UtcNow.ToString('o')
  $parentName = $null
  try {
    $self = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
    if ($null -ne $self) {
      $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($self.ParentProcessId)"
      if ($null -ne $parent) { $parentName = [string]$parent.Name }
    }
  } catch {
    $parentName = 'unknown'
  }

  Write-DahyeJsonAtomic -Path $resultPath -Value ([pscustomobject]@{
    schemaVersion = 1
    pass = $false
    status = 'running'
    port = $Port
    workerPid = $PID
    workerParent = $parentName
    startedAt = $startedAt
    completedAt = $null
  })
  Write-DahyeApplyLog -Path $logPath -Content "獨立重啟 worker 已啟動。`r`n"
  Remove-Item -LiteralPath $errorLogPath -Force -ErrorAction SilentlyContinue

  try {
    Start-Sleep -Milliseconds 1500
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startPath -Port $Port -RestartExisting 2>&1)
    $startExitCode = $LASTEXITCODE
    Write-DahyeApplyLog -Path $logPath -Content (($output | ForEach-Object { "$_" }) -join "`r`n")
    if ($startExitCode -ne 0) { throw "啟動器回傳失敗狀態：$startExitCode" }

    $statePath = Join-Path $stateRoot 'state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw '啟動器完成後找不到 skin state。' }
    $state = Read-DahyeState -Path $statePath
    if ($null -eq $state -or [int]$state.port -ne $Port -or [int]$state.injectorPid -le 0) {
      throw '啟動器完成後的 skin state 身分不完整。'
    }

    Write-DahyeJsonAtomic -Path $resultPath -Value ([pscustomobject]@{
      schemaVersion = 1
      pass = $true
      status = 'completed'
      port = $Port
      workerPid = $PID
      workerParent = $parentName
      injectorPid = [int]$state.injectorPid
      browserId = [string]$state.browserId
      startedAt = $startedAt
      completedAt = [DateTime]::UtcNow.ToString('o')
    })
    exit 0
  } catch {
    $message = $_.Exception.Message
    Write-DahyeApplyLog -Path $errorLogPath -Content ($message + "`r`n")
    Write-DahyeJsonAtomic -Path $resultPath -Value ([pscustomobject]@{
      schemaVersion = 1
      pass = $false
      status = 'failed'
      port = $Port
      workerPid = $PID
      workerParent = $parentName
      error = $message
      startedAt = $startedAt
      completedAt = [DateTime]::UtcNow.ToString('o')
    })
    exit 1
  }
}

Assert-DahyeRecoveryBaselineCurrent -BaselinePath $baselinePath | Out-Null
foreach ($path in @($resultPath, $dispatchPath, $logPath, $errorLogPath)) {
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

$worker = Start-DahyeDetachedWorker -WorkerScript $PSCommandPath -Port $Port
Write-DahyeJsonAtomic -Path $dispatchPath -Value ([pscustomobject]@{
  schemaVersion = 1
  workerPid = $worker.ProcessId
  parentKind = $worker.ParentKind
  port = $Port
  dispatchedAt = [DateTime]::UtcNow.ToString('o')
})
Write-Host "已將 Codex 重啟交給獨立的 Windows worker（PID $($worker.ProcessId)）；此視窗可安全關閉。"
