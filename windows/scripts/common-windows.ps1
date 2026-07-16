Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DahyeOperationMutexName {
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  "Local\CodexDahyeSkin.Operation.$sid"
}

function Enter-DahyeOperationLock {
  param([int]$TimeoutMilliseconds = 15000)
  $created = $false
  $mutex = New-Object Threading.Mutex($false, (Get-DahyeOperationMutexName), [ref]$created)
  if (-not $mutex.WaitOne($TimeoutMilliseconds)) {
    $mutex.Dispose()
    throw '另一個李多慧皮膚操作仍在執行。'
  }
  return $mutex
}

function Exit-DahyeOperationLock {
  param([Threading.Mutex]$Mutex)
  if ($null -eq $Mutex) { return }
  try { $Mutex.ReleaseMutex() } catch [ApplicationException] { }
  $Mutex.Dispose()
}

function Test-DahyePathWithin {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
  $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-DahyePathEqual {
  param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
  [IO.Path]::GetFullPath($Left).TrimEnd('\').Equals(
    [IO.Path]::GetFullPath($Right).TrimEnd('\'),
    [StringComparison]::OrdinalIgnoreCase
  )
}

function Test-DahyePortInUse {
  param([Parameter(Mandatory)][int]$Port)
  $client = New-Object Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne(150)) { return $false }
    $client.EndConnect($async)
    return $true
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

function Resolve-DahyePort {
  param(
    [Nullable[int]]$ExplicitPort,
    [int]$PreferredPort = 9435,
    [int]$ScanCount = 100,
    [scriptblock]$PortProbe = ${function:Test-DahyePortInUse}
  )
  if ($null -ne $ExplicitPort) {
    $explicitValue = [int]$ExplicitPort
    if (& $PortProbe $explicitValue) { throw "指定的連接埠 $explicitValue 已被占用。" }
    return $explicitValue
  }
  for ($port = $PreferredPort; $port -lt ($PreferredPort + $ScanCount); $port++) {
    if (-not (& $PortProbe $port)) { return $port }
  }
  throw "找不到可用的本機連接埠（$PreferredPort 起共 $ScanCount 個）。"
}

function Get-DahyeNodePath {
  param([int]$MinimumMajor = 22)
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($null -eq $command) { throw "找不到 Node.js；需要 Node.js $MinimumMajor 以上版本。" }
  $versionText = & $command.Source --version
  if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '^v(?<major>\d+)') { throw '無法判定 Node.js 版本。' }
  if ([int]$Matches.major -lt $MinimumMajor) { throw "Node.js 版本過舊；需要 $MinimumMajor 以上版本。" }
  return (Resolve-Path -LiteralPath $command.Source).Path
}

function Get-RegisteredCodexPackage {
  $packages = @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation } | Sort-Object Version -Descending)
  foreach ($package in $packages) {
    $root = (Resolve-Path -LiteralPath $package.InstallLocation).Path
    $executableCandidate = Join-Path $root 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $executableCandidate -PathType Leaf)) { continue }
    $executable = (Resolve-Path -LiteralPath $executableCandidate).Path
    if (-not (Test-DahyePathWithin -Path $executable -Root $root)) { continue }
    return [pscustomobject]@{
      Executable = $executable
      PackageRoot = $root
      PackageFullName = [string]$package.PackageFullName
      PackageFamilyName = [string]$package.PackageFamilyName
    }
  }
  throw '找不到可驗證的官方 OpenAI.Codex Store 套件。'
}

function Split-DahyeCommandLine {
  param([string]$CommandLine)
  if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }
  @([regex]::Matches($CommandLine, '"(?:\\.|[^"])*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
}

function Test-DahyeCommandLineToken {
  param([string]$CommandLine, [string]$Token, [string]$Value)
  $tokens = @(Split-DahyeCommandLine $CommandLine)
  for ($index = 0; $index -lt ($tokens.Count - 1); $index++) {
    if ($tokens[$index] -ceq $Token -and $tokens[$index + 1] -ceq $Value) { return $true }
  }
  return $false
}

function Get-DahyeBrowserIdentity {
  param([int]$Port)
  try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
    $url = [Uri]$version.webSocketDebuggerUrl
    if ($url.Host -notin @('127.0.0.1','localhost') -or $url.Port -ne $Port) { return $null }
    if ($url.AbsolutePath -match '/devtools/browser/(?<id>[^/]+)$') { return $Matches.id }
  } catch { return $null }
  return $null
}

function Test-DahyeLegacyStateActive {
  param(
    [Parameter(Mandatory)][string]$StatePath,
    [scriptblock]$ProcessQuery = { param($pid) Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue },
    [scriptblock]$BrowserIdentityQuery = { param($port) Get-DahyeBrowserIdentity -Port $port }
  )
  if (-not (Test-Path -LiteralPath $StatePath)) { return $false }
  try { $state = Get-Content -Raw -LiteralPath $StatePath -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
  foreach ($name in @('port','injectorPid','injectorPath','browserId')) {
    if ($null -eq $state.PSObject.Properties[$name]) { return $false }
  }
  $process = & $ProcessQuery ([int]$state.injectorPid)
  if ($null -eq $process -or [string]$process.Name -notmatch '^node(\.exe)?$') { return $false }
  $tokens = @(Split-DahyeCommandLine ([string]$process.CommandLine))
  if (-not ($tokens -contains [string]$state.injectorPath) -or -not ($tokens -contains '--watch')) { return $false }
  if (-not (Test-DahyeCommandLineToken $process.CommandLine '--port' ([string]$state.port))) { return $false }
  if ((& $BrowserIdentityQuery ([int]$state.port)) -cne [string]$state.browserId) { return $false }
  return $true
}

function Test-DahyeLegacyCommandActive {
  param([scriptblock]$ProcessQuery = { Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue })
  foreach ($process in @(& $ProcessQuery)) {
    $commandLine = [string]$process.CommandLine
    if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine -notmatch '(?i)injector\.mjs' -or $commandLine -notmatch '(?i)(^|\s)--watch(\s|$)') { continue }
    if ($commandLine -match '(?i)package-v1|CodexDahyeSkin') { continue }
    if ($commandLine -match '(?i)CodexDreamSkin|CodexFionaSkin|codex-dream-skin|codex-fiona') { return $true }
  }
  return $false
}

function Assert-NoLegacySkinSession {
  $roots = @(
    (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\state.json'),
    (Join-Path $env:LOCALAPPDATA 'CodexFionaSkin\state.json')
  )
  foreach ($statePath in $roots) {
    if (Test-DahyeLegacyStateActive -StatePath $statePath) {
      throw '偵測到 Dream/Fiona 皮膚仍在執行；請先使用舊版復原工具關閉。'
    }
  }
  if (Test-DahyeLegacyCommandActive) {
    throw '偵測到 Dream/Fiona injector 命令列仍在執行；請先使用舊版復原工具關閉。'
  }
}

function Get-DahyeProcessStartedAt {
  param([int]$ProcessId)
  try { (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o') } catch { $null }
}

function Test-DahyeRecordedProcess {
  param([Parameter(Mandatory)][pscustomobject]$State)
  $process = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$State.injectorPid)" -ErrorAction SilentlyContinue
  if ($null -eq $process -or [string]$process.Name -notmatch '^node(\.exe)?$') { return $false }
  if (-not (Test-DahyePathEqual -Left $process.ExecutablePath -Right $State.nodePath)) { return $false }
  $tokens = @(Split-DahyeCommandLine $process.CommandLine)
  if (-not ($tokens -contains [string]$State.injectorPath) -or -not ($tokens -contains '--watch')) { return $false }
  if (-not (Test-DahyeCommandLineToken $process.CommandLine '--port' ([string]$State.port))) { return $false }
  if (-not (Test-DahyeCommandLineToken $process.CommandLine '--browser-id' ([string]$State.browserId))) { return $false }
  $startedAt = Get-DahyeProcessStartedAt -ProcessId ([int]$State.injectorPid)
  return $startedAt -ceq [string]$State.injectorStartedAt
}

function Get-DahyeCodexProcesses {
  param([Parameter(Mandatory)][pscustomobject]$Package)
  @(
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        $_.ExecutablePath -and
        (Test-DahyePathWithin -Path $_.ExecutablePath -Root $Package.PackageRoot)
      }
  )
}

function Stop-DahyeVerifiedCodexProcesses {
  param(
    [Parameter(Mandatory)][pscustomobject]$Package,
    [Nullable[int]]$Port,
    [switch]$AllVerified
  )
  foreach ($process in @(Get-DahyeCodexProcesses -Package $Package)) {
    if (-not $AllVerified) {
      $portToken = "--remote-debugging-port=$([int]$Port)"
      if (-not (@(Split-DahyeCommandLine $process.CommandLine) -contains $portToken)) { continue }
    }
    Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
  }
}

function Wait-DahyeBrowserIdentity {
  param([Parameter(Mandatory)][int]$Port, [int]$TimeoutSeconds = 30)
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $browserId = Get-DahyeBrowserIdentity -Port $Port
    if ($browserId) { return $browserId }
    Start-Sleep -Milliseconds 300
  }
  throw "無法在 $TimeoutSeconds 秒內取得 Codex Browser ID。"
}

function Wait-DahyePortClosed {
  param([Parameter(Mandatory)][int]$Port, [int]$TimeoutSeconds = 15)
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (-not (Test-DahyePortInUse -Port $Port)) { return $true }
    Start-Sleep -Milliseconds 250
  }
  throw "李多慧皮膚連接埠 $Port 未能關閉。"
}

function Open-DahyeOfficialCodex {
  Start-Process explorer.exe 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
}

function New-DahyeRuntimeState {
  param(
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][Diagnostics.Process]$Injector,
    [Parameter(Mandatory)][string]$InjectorPath,
    [Parameter(Mandatory)][string]$NodePath,
    [Parameter(Mandatory)][pscustomobject]$Package,
    [Parameter(Mandatory)][string]$BrowserId,
    [Parameter(Mandatory)][string]$RecoveryBaselinePath
  )
  [pscustomobject]@{
    schemaVersion = 1
    platform = 'windows'
    port = $Port
    injectorPid = $Injector.Id
    injectorStartedAt = $Injector.StartTime.ToUniversalTime().ToString('o')
    injectorPath = $InjectorPath
    nodePath = $NodePath
    codexExe = $Package.Executable
    codexPackageRoot = $Package.PackageRoot
    codexPackageFullName = $Package.PackageFullName
    codexPackageFamilyName = $Package.PackageFamilyName
    browserId = $BrowserId
    startedAt = [DateTime]::UtcNow.ToString('o')
    recoveryBaselinePath = $RecoveryBaselinePath
  }
}

function Invoke-DahyeStartRollback {
  param(
    [Diagnostics.Process]$Injector,
    [pscustomobject]$Package,
    [Nullable[int]]$Port,
    [string]$StatePath,
    [switch]$RelaunchOfficial
  )
  if ($Injector -and -not $Injector.HasExited) {
    Stop-Process -Id $Injector.Id -Force -ErrorAction SilentlyContinue
  }
  if ($Package -and $null -ne $Port) {
    Stop-DahyeVerifiedCodexProcesses -Package $Package -Port $Port -ErrorAction SilentlyContinue
  }
  if ($StatePath -and (Test-Path -LiteralPath $StatePath)) {
    Archive-DahyeState -StatePath $StatePath -Reason 'start-failed' | Out-Null
  }
  if ($RelaunchOfficial) { Open-DahyeOfficialCodex }
}
