Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-DahyeDetachedWorker {
  param(
    [Parameter(Mandatory)][string]$WorkerScript,
    [Parameter(Mandatory)][ValidateRange(1024, 65535)][int]$Port,
    [scriptblock]$ProcessCreator
  )

  $workerPath = [IO.Path]::GetFullPath($WorkerScript)
  $quotedWorkerPath = $workerPath.Replace("'", "''")
  $workerSource = "& '$quotedWorkerPath' -DetachedWorker -Port $Port"
  $encodedWorker = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($workerSource))
  $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $commandLine = '"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand {1}' -f `
    $powerShellPath, $encodedWorker

  if ($null -ne $ProcessCreator) {
    $created = & $ProcessCreator $commandLine
  } else {
    # Win32_Process.Create 由 WMI Provider Host（WmiPrvSE）建立程序，因此不會繼承 Codex 的程序工作群組。
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $commandLine }
  }

  if ($null -eq $created -or [int]$created.ReturnValue -ne 0 -or [int]$created.ProcessId -le 0) {
    $returnValue = if ($null -eq $created) { 'null' } else { [string]$created.ReturnValue }
    throw "Windows 無法建立獨立重啟 worker（Win32_Process.Create=$returnValue）。"
  }

  [pscustomobject]@{
    ProcessId = [int]$created.ProcessId
    ParentKind = 'WmiPrvSE'
  }
}
