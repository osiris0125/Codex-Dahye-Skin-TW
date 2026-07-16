Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DahyeStateFields = @(
  'schemaVersion','platform','port','injectorPid','injectorStartedAt','injectorPath',
  'nodePath','codexExe','codexPackageRoot','codexPackageFullName',
  'codexPackageFamilyName','browserId','startedAt','recoveryBaselinePath'
)

function Get-DahyeStateRoot {
  Join-Path $env:LOCALAPPDATA 'CodexDahyeSkin\runtime'
}

function Assert-DahyeStateSchema {
  param([Parameter(Mandatory)] [pscustomobject]$State)
  foreach ($name in $script:DahyeStateFields) {
    if ($null -eq $State.PSObject.Properties[$name]) { throw "Dahye state 缺少欄位：$name" }
  }
  if ([int]$State.schemaVersion -ne 1 -or [string]$State.platform -cne 'windows') {
    throw 'Dahye state 版本或平台不符。'
  }
  if ([int]$State.port -lt 1 -or [int]$State.port -gt 65535) { throw 'Dahye state 連接埠不合法。' }
}

function Write-DahyeJsonAtomic {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
  $directory = Split-Path -Parent $Path
  [IO.Directory]::CreateDirectory($directory) | Out-Null
  $tempPath = Join-Path $directory ('.dahye-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $json = $Value | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }
}

function Write-DahyeState {
  param([Parameter(Mandatory)][pscustomobject]$State, [Parameter(Mandatory)][string]$StatePath)
  Assert-DahyeStateSchema -State $State
  Write-DahyeJsonAtomic -Value $State -Path $StatePath
}

function Read-DahyeState {
  param([Parameter(Mandatory)][string]$StatePath)
  if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
  $state = Get-Content -Raw -LiteralPath $StatePath -Encoding UTF8 | ConvertFrom-Json
  Assert-DahyeStateSchema -State $state
  return $state
}

function Archive-DahyeState {
  param([Parameter(Mandatory)][string]$StatePath, [Parameter(Mandatory)][string]$Reason)
  if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
  $archiveRoot = Join-Path (Split-Path -Parent $StatePath) 'archive'
  [IO.Directory]::CreateDirectory($archiveRoot) | Out-Null
  $safeReason = $Reason -replace '[^A-Za-z0-9_-]', '-'
  $destination = Join-Path $archiveRoot ("state-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), $safeReason)
  Move-Item -LiteralPath $StatePath -Destination $destination
  return $destination
}
