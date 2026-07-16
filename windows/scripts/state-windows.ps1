Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DahyeStateRoot {
  Join-Path $env:LOCALAPPDATA 'CodexDahyeSkin\runtime'
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
