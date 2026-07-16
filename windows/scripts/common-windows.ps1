. (Join-Path $PSScriptRoot 'io-windows.ps1')

function Get-DahyeOperationMutexName {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  return "Local\CodexDahyeSkin.Operation.$sid"
}

function Enter-DahyeOperationLock {
  $mutex = [System.Threading.Mutex]::new($false, (Get-DahyeOperationMutexName))
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
  }
  if (-not $acquired) {
    $mutex.Dispose()
    throw '另一個李多慧繁體中文皮膚的安裝、啟動、復原或驗證程序正在執行。'
  }
  return $mutex
}

function Exit-DahyeOperationLock {
  param([Parameter(Mandatory = $true)][System.Threading.Mutex]$Mutex)
  try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Assert-DahyePort {
  param([Parameter(Mandatory = $true)][int]$Port)
  if ($Port -lt 1024 -or $Port -gt 65535) { throw "連接埠必須介於 1024 到 65535：$Port" }
}

function Test-DahyePathEqual {
  param([string]$Left, [string]$Right)
  if (-not $Left -or -not $Right) { return $false }
  try {
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\'))
  } catch {
    return $false
  }
}

function Test-DahyePathWithin {
  param([string]$Path, [string]$Root)
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $prefix = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Split-DahyeCommandLine {
  param([string]$CommandLine)
  if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }
  return @([regex]::Matches($CommandLine, '"(?:\\.|[^"])*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
}

function Test-DahyeCommandLineToken {
  param([string]$CommandLine, [string]$Token, [string]$Value)
  if (-not $CommandLine -or -not $Token) { return $false }
  if ($PSBoundParameters.ContainsKey('Value')) {
    $tokens = @(Split-DahyeCommandLine -CommandLine $CommandLine)
    for ($index = 0; $index -lt ($tokens.Count - 1); $index++) {
      if ($tokens[$index] -ceq $Token -and $tokens[$index + 1] -ceq $Value) { return $true }
    }
    return $false
  }
  $pattern = '(?i)(?:^|[\s"])' + [regex]::Escape($Token) + '(?=$|[\s"])'
  return [regex]::IsMatch($CommandLine, $pattern)
}

function ConvertTo-DahyeProcessArgument {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  if ($Value.Contains('"')) { throw '程序參數不可包含雙引號。' }
  if ($Value -notmatch '\s') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

function Get-DahyeProcessExecutablePath {
  param([Parameter(Mandatory = $true)][object]$ProcessInfo)
  if ($ProcessInfo.ExecutablePath) { return "$($ProcessInfo.ExecutablePath)" }
  try {
    $process = Get-Process -Id ([int]$ProcessInfo.ProcessId) -ErrorAction Stop
    if ($process.Path) { return "$($process.Path)" }
    return "$($process.MainModule.FileName)"
  } catch {
    return $null
  }
}

function Get-DahyeNodeRuntime {
  param([int]$MinimumMajor = 22)

  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if (-not $command) { throw "需要 Node.js $MinimumMajor 以上版本，但在 PATH 中找不到。" }
  $version = "$(& $command.Source -p 'process.versions.node' 2>$null)".Trim()
  if ($LASTEXITCODE -ne 0 -or -not $version) { throw '無法驗證 Node.js 執行環境。' }
  $runtimePath = "$(& $command.Source -p 'process.execPath' 2>$null)".Trim()
  if ($LASTEXITCODE -ne 0 -or -not $runtimePath -or -not (Test-Path -LiteralPath $runtimePath)) {
    throw '無法驗證 Node.js 執行檔路徑。'
  }
  $major = 0
  if (-not [int]::TryParse(($version -split '\.')[0], [ref]$major) -or $major -lt $MinimumMajor) {
    throw "需要 Node.js $MinimumMajor 以上版本；目前在 $runtimePath 找到 $version。"
  }
  return [pscustomobject]@{ Path = $runtimePath; Version = $version; Major = $major }
}

function ConvertTo-DahyeCodexInstall {
  param([Parameter(Mandatory = $true)][object]$Package)
  if ("$($Package.Name)" -ine 'OpenAI.Codex' -or -not $Package.InstallLocation -or
    -not $Package.PackageFullName -or -not $Package.PackageFamilyName -or
    "$($Package.SignatureKind)" -ine 'Store' -or [bool]$Package.IsDevelopmentMode) {
    return $null
  }
  $packageRoot = "$($Package.InstallLocation)"
  $executable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-Path -LiteralPath $executable)) { return $null }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($Package.Version)"
    PackageFullName = "$($Package.PackageFullName)"
    PackageFamilyName = "$($Package.PackageFamilyName)"
    SignatureKind = "$($Package.SignatureKind)"
  }
}

function Get-DahyeRegisteredCodexInstalls {
  $packages = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Sort-Object Version -Descending)
  $installs = @()
  foreach ($package in $packages) {
    $install = ConvertTo-DahyeCodexInstall -Package $package
    if ($null -ne $install) { $installs += $install }
  }
  return $installs
}

function Get-DahyeCodexInstall {
  $installs = @(Get-DahyeRegisteredCodexInstalls)
  if ($installs.Count -eq 0) { throw '尚未安裝官方 OpenAI.Codex Store 套件，或無法驗證其套件身分。' }
  return $installs[0]
}

function Get-DahyeCodexStatePathCandidate {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.codexExe -or -not $State.codexPackageRoot) { return $null }
  $executable = "$($State.codexExe)"
  $packageRoot = "$($State.codexPackageRoot)"
  $expectedExecutable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-DahyePathEqual -Left $executable -Right $expectedExecutable)) { return $null }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($State.codexVersion)"
    FromState = $true
    RegisteredPackageVerified = $false
  }
}

function Resolve-DahyeCodexInstallFromState {
  param(
    [AllowNull()][object]$State,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RegisteredInstalls
  )
  $candidate = Get-DahyeCodexStatePathCandidate -State $State
  if ($null -eq $candidate) { return $null }

  $hasFullName = [bool]$State.codexPackageFullName
  $hasFamilyName = [bool]$State.codexPackageFamilyName
  if ($hasFullName -xor $hasFamilyName) { return $null }
  foreach ($install in $RegisteredInstalls) {
    $pathMatches = (Test-DahyePathEqual -Left $candidate.PackageRoot -Right $install.PackageRoot) -and
      (Test-DahyePathEqual -Left $candidate.Executable -Right $install.Executable)
    if (-not $pathMatches) { continue }
    if ($hasFullName -and ("$($State.codexPackageFullName)" -ine $install.PackageFullName -or
      "$($State.codexPackageFamilyName)" -ine $install.PackageFamilyName)) {
      continue
    }
    return [pscustomobject]@{
      PackageRoot = $install.PackageRoot
      Executable = $install.Executable
      Version = $install.Version
      PackageFullName = $install.PackageFullName
      PackageFamilyName = $install.PackageFamilyName
      SignatureKind = $install.SignatureKind
      FromState = $true
      RegisteredPackageVerified = $true
    }
  }
  return $null
}

function Get-DahyeCodexInstallFromState {
  param([AllowNull()][object]$State)
  try { $installs = @(Get-DahyeRegisteredCodexInstalls) } catch { return $null }
  return Resolve-DahyeCodexInstallFromState -State $State -RegisteredInstalls $installs
}

function Test-DahyeWebSocketUrl {
  param([string]$Value, [int]$Port)
  try {
    $uri = [Uri]$Value
    $hostName = $uri.Host.ToLowerInvariant()
    return ($uri.IsAbsoluteUri -and $uri.Scheme -eq 'ws' -and $uri.Port -eq $Port -and
      $hostName -in @('127.0.0.1', 'localhost', '::1', '[::1]') -and -not $uri.UserInfo -and
      -not $uri.Query -and -not $uri.Fragment -and
      $uri.AbsolutePath -cmatch '^/devtools/(?:page|browser)/[A-Za-z0-9._-]{1,200}$')
  } catch {
    return $false
  }
}

function Test-DahyeCdpPageTarget {
  param([AllowNull()][object]$Target, [int]$Port)
  if ($null -eq $Target -or "$($Target.type)" -cne 'page' -or
    "$($Target.url)" -notlike 'app://*') {
    return $false
  }
  if ($Target.id -isnot [string]) { return $false }
  $targetId = "$($Target.id)"
  $webSocketUrl = "$($Target.webSocketDebuggerUrl)"
  if (-not (Test-DahyeBrowserId -Value $targetId) -or
    -not (Test-DahyeWebSocketUrl -Value $webSocketUrl -Port $Port)) {
    return $false
  }
  try {
    return ([Uri]$webSocketUrl).AbsolutePath -ceq "/devtools/page/$targetId"
  } catch {
    return $false
  }
}

function Get-DahyeCdpTargets {
  param([int]$Port)
  try {
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2 `
      -MaximumRedirection 0 -ErrorAction Stop
    return @($targets | Where-Object { Test-DahyeCdpPageTarget -Target $_ -Port $Port })
  } catch {
    return @()
  }
}

function Test-DahyeBrowserId {
  param([string]$Value)
  return [bool]($Value -and $Value.Length -le 200 -and $Value -cmatch '^[A-Za-z0-9._-]+$')
}

function Get-DahyeCdpBrowserIdentity {
  param([int]$Port)
  try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 `
      -MaximumRedirection 0 -ErrorAction Stop
    $webSocketUrl = "$($version.webSocketDebuggerUrl)"
    if (-not (Test-DahyeWebSocketUrl -Value $webSocketUrl -Port $Port)) { return $null }
    $uri = [Uri]$webSocketUrl
    $match = [regex]::Match($uri.AbsolutePath, '^/devtools/browser/(?<id>[A-Za-z0-9._-]{1,200})$')
    if (-not $match.Success -or $uri.Query -or $uri.Fragment) { return $null }
    $browserId = $match.Groups['id'].Value
    if (-not (Test-DahyeBrowserId -Value $browserId)) { return $null }
    return [pscustomobject]@{
      BrowserId = $browserId
      WebSocketDebuggerUrl = $webSocketUrl
      Browser = "$($version.Browser)"
    }
  } catch {
    return $null
  }
}

function Get-DahyePortListeners {
  param([int]$Port)
  if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
    throw '需要 Get-NetTCPConnection 才能驗證 CDP 監聽程序的擁有者。'
  }
  return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Test-DahyePortAvailable {
  param(
    [int]$Port,
    [scriptblock]$ListenerQuery = { param($candidatePort) @(Get-DahyePortListeners -Port $candidatePort) }
  )
  $listeners = @(& $ListenerQuery $Port)
  return $listeners.Count -eq 0
}

function Test-DahyeCodexPortOwner {
  param(
    [int]$Port,
    [Parameter(Mandatory = $true)][object]$Codex,
    [scriptblock]$ListenerQuery = { param($candidatePort) @(Get-DahyePortListeners -Port $candidatePort) }
  )
  $listeners = @(& $ListenerQuery $Port)
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listener in $listeners) {
    if ($listener.LocalAddress -notin @('127.0.0.1', '::1')) { return $false }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue
    $processPath = if ($process) { Get-DahyeProcessExecutablePath -ProcessInfo $process } else { $null }
    if (-not $processPath -or -not (Test-DahyePathEqual -Left $processPath -Right $Codex.Executable)) {
      return $false
    }
  }
  return $true
}

function Get-DahyeVerifiedCdpIdentity {
  param([int]$Port, [Parameter(Mandatory = $true)][object]$Codex)
  if (-not (Test-DahyeCodexPortOwner -Port $Port -Codex $Codex)) { return $null }
  $browser = Get-DahyeCdpBrowserIdentity -Port $Port
  if ($null -eq $browser) { return $null }
  $targets = @(Get-DahyeCdpTargets -Port $Port)
  if ($targets.Count -eq 0) { return $null }
  if (-not (Test-DahyeCodexPortOwner -Port $Port -Codex $Codex)) { return $null }
  return [pscustomobject]@{
    BrowserId = $browser.BrowserId
    BrowserWebSocketDebuggerUrl = $browser.WebSocketDebuggerUrl
    Browser = $browser.Browser
    TargetCount = $targets.Count
  }
}

function Test-DahyeCodexCdpEndpoint {
  param([int]$Port, [Parameter(Mandatory = $true)][object]$Codex)
  return $null -ne (Get-DahyeVerifiedCdpIdentity -Port $Port -Codex $Codex)
}

function Select-DahyePort {
  param([int]$PreferredPort)
  for ($candidate = $PreferredPort; $candidate -le [Math]::Min(65535, $PreferredPort + 100); $candidate++) {
    if (Test-DahyePortAvailable -Port $candidate) { return $candidate }
  }
  throw "在 $PreferredPort 到 $([Math]::Min(65535, $PreferredPort + 100)) 之間找不到可用的本機回環連接埠。"
}

function Wait-DahyePortAvailable {
  param([int]$Port, [int]$TimeoutSeconds = 5)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-DahyePortAvailable -Port $Port) { return $true }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Read-DahyeState {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $state = (Read-DahyeUtf8File -Path $Path) | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $state -or $state -is [string] -or $state -is [array]) { throw '狀態檔根節點必須是物件。' }
    $properties = @($state.PSObject.Properties.Name)
    if ($properties -contains 'platform' -and "$($state.platform)" -ine 'windows') {
      throw '狀態檔記錄的平台不是 Windows。'
    }
    $schemaVersion = 1
    if ($properties -contains 'schemaVersion') {
      $schemaVersion = 0
      if (-not [int]::TryParse("$($state.schemaVersion)", [ref]$schemaVersion) -or
        $schemaVersion -lt 1 -or $schemaVersion -gt 3) {
        throw '不支援此狀態檔結構版本。'
      }
    }
    if ($schemaVersion -ge 3) {
      foreach ($required in @(
        'platform', 'port', 'injectorPid', 'injectorStartedAt', 'injectorPath', 'nodePath',
        'codexExe', 'codexPackageRoot', 'codexPackageFullName', 'codexPackageFamilyName', 'browserId'
      )) {
        if ($properties -notcontains $required -or -not $state.$required) {
          throw "狀態檔結構版本 3 缺少必要欄位：$required"
        }
      }
    }
    if ($properties -contains 'port') {
      $statePort = 0
      if (-not [int]::TryParse("$($state.port)", [ref]$statePort)) { throw '狀態檔中的連接埠無效。' }
      Assert-DahyePort -Port $statePort
    }
    if ($properties -contains 'injectorPid' -and $null -ne $state.injectorPid) {
      $statePid = 0
      if (-not [int]::TryParse("$($state.injectorPid)", [ref]$statePid) -or $statePid -le 0) {
        throw '狀態檔中的注入程序 PID 無效。'
      }
    }
    if ($properties -contains 'browserId' -and $state.browserId -and
      -not (Test-DahyeBrowserId -Value "$($state.browserId)")) {
      throw '狀態檔中的瀏覽器 ID 無效。'
    }
    return $state
  } catch {
    throw "李多慧繁體中文皮膚狀態檔無法讀取，已原樣保留供檢查：$Path"
  }
}

function Write-DahyeState {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$State)
  $json = $State | ConvertTo-Json -Depth 6
  Write-DahyeUtf8FileAtomically -Path $Path -Content ($json + "`r`n")
}

function Archive-DahyeStateFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
  $archivePath = Join-Path $directory "state.stale-$stamp-$([guid]::NewGuid().ToString('N')).json"
  Move-Item -LiteralPath $Path -Destination $archivePath -ErrorAction Stop
  return $archivePath
}

function Get-DahyeProcessStartedAt {
  param([int]$ProcessId)
  try {
    return (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')
  } catch {
    return $null
  }
}

function Stop-DahyeRecordedInjector {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.injectorPid) { return $true }
  $processId = [int]$State.injectorPid
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
  if (-not $process) { return $true }

  $expectedInjector = if ($State.injectorPath) {
    "$($State.injectorPath)"
  } elseif ($State.skillRoot) {
    Join-Path "$($State.skillRoot)" 'scripts\injector.mjs'
  } else {
    $null
  }
  $processPath = Get-DahyeProcessExecutablePath -ProcessInfo $process
  $commandLine = "$($process.CommandLine)"
  if (-not $processPath -or -not $commandLine) {
    throw "已記錄的注入程序 PID $processId 仍在執行，但無法檢查其身分；狀態檔已保留。"
  }
  $isNodeExecutable = [System.IO.Path]::GetFileName("$processPath") -ieq 'node.exe'
  $nodeMatches = -not $State.nodePath -or
    (Test-DahyePathEqual -Left $processPath -Right "$($State.nodePath)")
  $injectorMatches = [bool]($expectedInjector -and
    (Test-DahyeCommandLineToken -CommandLine $commandLine -Token $expectedInjector) -and
    (Test-DahyeCommandLineToken -CommandLine $commandLine -Token '--watch'))
  if ($State.port) {
    $portPattern = '(?i)(?:^|\s)--port(?:=|\s+)' + [regex]::Escape("$($State.port)") + '(?=$|\s)'
    $injectorMatches = $injectorMatches -and [regex]::IsMatch($commandLine, $portPattern)
  } else {
    $injectorMatches = $false
  }
  if ($State.browserId) {
    $browserPattern = '(?:^|\s)(?i:--browser-id)(?:=|\s+)' + [regex]::Escape("$($State.browserId)") + '(?=$|\s)'
    $injectorMatches = $injectorMatches -and [regex]::IsMatch($commandLine, $browserPattern)
  }
  $startedAt = Get-DahyeProcessStartedAt -ProcessId $processId
  $startMatches = -not $State.injectorStartedAt -or $startedAt -eq "$($State.injectorStartedAt)"
  $identityMatches = [bool]($isNodeExecutable -and $nodeMatches -and $injectorMatches -and $startMatches)

  if (-not $identityMatches) {
    Write-Warning "已略過過期的注入程序 PID $processId，因為可見身分與已儲存的李多慧繁體中文皮膚程序不符。"
    return $false
  }

  Stop-Process -Id $processId -Force -ErrorAction Stop
  try { Wait-Process -Id $processId -Timeout 5 -ErrorAction Stop } catch {}
  if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
    throw "已記錄的李多慧繁體中文皮膚注入程序未停止：PID $processId"
  }
  return $true
}

function Get-DahyeCodexProcesses {
  param([Parameter(Mandatory = $true)][object]$Codex)
  return @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $processPath = Get-DahyeProcessExecutablePath -ProcessInfo $_
      Test-DahyePathEqual -Left $processPath -Right $Codex.Executable
    })
}

function Stop-DahyeCodex {
  param(
    [Parameter(Mandatory = $true)][Alias('Package')][object]$Codex,
    [switch]$AllowForce,
    [scriptblock]$ProcessQuery = { param($candidate) @(Get-DahyeCodexProcesses -Codex $candidate) },
    [scriptblock]$CloseRequest = {
      param($item)
      try { [void](Get-Process -Id $item.ProcessId -ErrorAction Stop).CloseMainWindow() } catch {}
    },
    [scriptblock]$ForceStop = {
      param($item, $candidate)
      $current = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$item.ProcessId)" -ErrorAction SilentlyContinue
      $currentPath = if ($current) { Get-DahyeProcessExecutablePath -ProcessInfo $current } else { $null }
      if ($currentPath -and (Test-DahyePathEqual -Left $currentPath -Right $candidate.Executable)) {
        Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue
      }
    },
    [scriptblock]$Delay = { param($milliseconds) Start-Sleep -Milliseconds $milliseconds },
    [int]$GracePeriodMilliseconds = 15000
  )
  $processes = @(& $ProcessQuery $Codex)
  if ($processes.Count -eq 0) { return }
  foreach ($item in $processes) {
    & $CloseRequest $item
  }

  $deadline = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(0, $GracePeriodMilliseconds))
  while ([DateTime]::UtcNow -lt $deadline) {
    if (@(& $ProcessQuery $Codex).Count -eq 0) { return }
    & $Delay 250
  }
  $remaining = @(& $ProcessQuery $Codex)
  if ($remaining.Count -eq 0) { return }
  if (-not $AllowForce) {
    throw 'Codex 未能在等待時間內關閉；請手動關閉，或明確允許強制重啟。'
  }
  foreach ($item in $remaining) {
    & $ForceStop $item $Codex
  }
  & $Delay 500
  if (@(& $ProcessQuery $Codex).Count -gt 0) { throw '無法安全停止 Codex。' }
}

function Confirm-DahyeRestart {
  param([string]$Message)
  $shell = New-Object -ComObject WScript.Shell
  return $shell.Popup($Message, 0, 'Codex 李多慧繁體中文皮膚', 52) -eq 6
}

function Get-RegisteredCodexPackage {
  Get-DahyeCodexInstall
}

function Get-DahyeNodePath {
  param([int]$MinimumMajor = 22)
  (Get-DahyeNodeRuntime -MinimumMajor $MinimumMajor).Path
}

function Get-DahyeBrowserIdentity {
  param([int]$Port)
  $identity = Get-DahyeCdpBrowserIdentity -Port $Port
  if ($null -eq $identity) { return $null }
  return $identity.BrowserId
}

function Wait-DahyePortClosed {
  param([Parameter(Mandatory)][int]$Port, [int]$TimeoutSeconds = 15)
  if (-not (Wait-DahyePortAvailable -Port $Port -TimeoutSeconds $TimeoutSeconds)) {
    throw "李多慧皮膚連接埠 $Port 未能關閉。"
  }
  return $true
}

function Open-DahyeOfficialCodex {
  $codex = Get-DahyeCodexInstall
  Start-Process -FilePath $codex.Executable | Out-Null
}

function Test-DahyeLegacyStateActive {
  param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [scriptblock]$ProcessQuery = { param($pid) Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue },
    [scriptblock]$BrowserIdentityQuery = { param($port) Get-DahyeBrowserIdentity -Port $port }
  )
  if (-not (Test-Path -LiteralPath $StatePath)) { return $false }
  try { $state = Get-Content -Raw -LiteralPath $StatePath -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
  foreach ($name in @('port', 'injectorPid', 'injectorPath', 'browserId')) {
    if ($null -eq $state.PSObject.Properties[$name]) { return $false }
  }
  $process = & $ProcessQuery ([int]$state.injectorPid)
  if ($null -eq $process -or [string]$process.Name -notmatch '^node(\.exe)?$') { return $false }
  $tokens = @(Split-DahyeCommandLine -CommandLine ([string]$process.CommandLine))
  if (-not ($tokens -contains [string]$state.injectorPath) -or -not ($tokens -contains '--watch')) { return $false }
  if (-not (Test-DahyeCommandLineToken -CommandLine $process.CommandLine -Token '--port' -Value ([string]$state.port))) { return $false }
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
  $statePaths = @(
    (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\state.json'),
    (Join-Path $env:LOCALAPPDATA 'CodexFionaSkin\state.json')
  )
  foreach ($statePath in $statePaths) {
    if (Test-DahyeLegacyStateActive -StatePath $statePath) {
      throw '偵測到 Dream/Fiona 皮膚仍在執行；請先使用舊版復原工具關閉。'
    }
  }
  if (Test-DahyeLegacyCommandActive) {
    throw '偵測到 Dream/Fiona 注入程序仍在執行；請先使用舊版復原工具關閉。'
  }
}
