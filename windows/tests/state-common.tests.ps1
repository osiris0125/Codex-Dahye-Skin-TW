Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\scripts\state-windows.ps1')
. (Join-Path $PSScriptRoot '..\scripts\common-windows.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
  if ($Actual -cne $Expected) { throw "$Message；actual=$Actual expected=$Expected" }
}

$temp = Join-Path $env:TEMP ("dahye-state-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $statePath = Join-Path $temp 'state.json'
  $state = [pscustomobject]@{
    schemaVersion = 1
    platform = 'windows'
    port = 9435
    injectorPid = 3210
    injectorStartedAt = '2026-07-16T10:00:00.0000000Z'
    injectorPath = 'C:\Dahye\windows\scripts\injector.mjs'
    nodePath = 'C:\Node\node.exe'
    codexExe = 'C:\Store\app\ChatGPT.exe'
    codexPackageRoot = 'C:\Store\app'
    codexPackageFullName = 'OpenAI.Codex_1.0.0.0_x64__2p2nqsd0c76g0'
    codexPackageFamilyName = 'OpenAI.Codex_2p2nqsd0c76g0'
    browserId = 'browser-abc'
    startedAt = '2026-07-16T10:00:02.0000000Z'
    recoveryBaselinePath = 'C:\State\recovery-baseline.json'
  }

  Write-DahyeState -State $state -StatePath $statePath
  $bytes = [IO.File]::ReadAllBytes($statePath)
  Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'state 必須是無 BOM UTF-8。'
  $roundTrip = Read-DahyeState -StatePath $statePath
  Assert-Equal $roundTrip.browserId 'browser-abc' 'Browser ID round-trip 失敗'

  Assert-Equal (Resolve-DahyePort -ExplicitPort 9440 -PreferredPort 9435 -ScanCount 100 -PortProbe { param($port) $false }) 9440 '明確 port 應保留'
  Assert-Equal (Resolve-DahyePort -ExplicitPort $null -PreferredPort 9435 -ScanCount 100 -PortProbe { param($port) $port -eq 9435 }) 9436 '應避開占用 port'
  $explicitBusy = $false
  try { Resolve-DahyePort -ExplicitPort 9440 -PortProbe { param($port) $true } | Out-Null } catch { $explicitBusy = $true }
  Assert-True $explicitBusy '明確 port 被占用必須失敗'
  Assert-True ((Get-DahyeOperationMutexName) -match '^Local\\CodexDahyeSkin\.Operation\.S-1-') 'mutex 必須包含使用者 SID'
  Assert-True ((Get-DahyeStateRoot) -like '*\CodexDahyeSkin\runtime') 'state 必須位於獨立 runtime 目錄'
  Assert-True (Test-DahyePathEqual -Left 'C:\Store\App\ChatGPT.exe' -Right 'c:\store\app\ChatGPT.exe') 'Windows 路徑比較必須不分大小寫'

  $legacyPath = Join-Path $temp 'legacy-state.json'
  [IO.File]::WriteAllText($legacyPath, '{"port":9335,"injectorPid":777,"injectorPath":"C:\\Old\\injector.mjs","browserId":"legacy-browser"}', [Text.UTF8Encoding]::new($false))
  $before = (Get-FileHash $legacyPath -Algorithm SHA256).Hash
  $active = Test-DahyeLegacyStateActive -StatePath $legacyPath -ProcessQuery {
    [pscustomobject]@{ ProcessId=777; Name='node.exe'; ExecutablePath='C:\Node\node.exe'; CommandLine='node.exe "C:\Old\injector.mjs" --watch --port 9335 --browser-id legacy-browser' }
  } -BrowserIdentityQuery { param($port) 'legacy-browser' }
  Assert-True $active '完整匹配的 legacy 工作階段應判 active'
  Assert-Equal (Get-FileHash $legacyPath -Algorithm SHA256).Hash $before 'legacy state 不得被修改'
  $oldCommandActive = Test-DahyeLegacyCommandActive -ProcessQuery {
    @(
      [pscustomobject]@{ Name='node.exe'; CommandLine='node.exe C:\Users\me\AppData\Local\CodexDreamSkin\package-legacy\windows\scripts\injector.mjs --watch --port 9335' }
    )
  }
  Assert-True $oldCommandActive '即使 state 遺失，也應偵測舊 injector 命令列'
  $newCommandActive = Test-DahyeLegacyCommandActive -ProcessQuery {
    @(
      [pscustomobject]@{ Name='node.exe'; CommandLine='node.exe C:\Users\me\AppData\Local\CodexDahyeSkin\package-v1\windows\scripts\injector.mjs --watch --port 9435' }
    )
  }
  Assert-True (-not $newCommandActive) 'Dahye sibling 不得被誤判為舊 injector'

  $archive = Archive-DahyeState -StatePath $statePath -Reason 'test'
  Assert-True (Test-Path $archive) '新 state 未封存'
  Assert-True (-not (Test-Path $statePath)) '封存後原 state 仍存在'
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS state-common.tests.ps1'
