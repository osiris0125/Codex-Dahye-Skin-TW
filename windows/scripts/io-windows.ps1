Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DahyeUtf8NoBom = [Text.UTF8Encoding]::new($false, $true)

function ConvertFrom-DahyeUtf8Bytes {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
    [Parameter(Mandatory)][string]$Path
  )
  try {
    $offset = if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { 3 } else { 0 }
    $content = $script:DahyeUtf8NoBom.GetString($Bytes, $offset, $Bytes.Length - $offset)
    if ($content.IndexOf([char]0) -ge 0) { throw "拒絕讀寫含 NUL 字元的檔案：$Path" }
    return $content
  } catch [Text.DecoderFallbackException] {
    throw "拒絕讀寫不是有效 UTF-8 的檔案：$Path"
  }
}

function Test-DahyeBytesEqual {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Left,
    [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Right
  )
  if ($Left.Length -ne $Right.Length) { return $false }
  for ($index = 0; $index -lt $Left.Length; $index++) {
    if ($Left[$index] -ne $Right[$index]) { return $false }
  }
  return $true
}

function Assert-DahyeFileUnchanged {
  param([Parameter(Mandatory)][string]$Path, [AllowNull()][byte[]]$ExpectedBytes)
  if ($null -eq $ExpectedBytes) {
    if (Test-Path -LiteralPath $Path) { throw "寫入期間檔案被建立，安全停止：$Path" }
    return
  }
  if (-not (Test-Path -LiteralPath $Path)) { throw "寫入期間檔案消失，安全停止：$Path" }
  $current = [IO.File]::ReadAllBytes($Path)
  if (-not (Test-DahyeBytesEqual -Left $ExpectedBytes -Right $current)) {
    throw "寫入期間檔案已變更，安全停止：$Path"
  }
}

function Read-DahyeUtf8File {
  param([Parameter(Mandatory)][string]$Path)
  ConvertFrom-DahyeUtf8Bytes -Bytes ([IO.File]::ReadAllBytes($Path)) -Path $Path
}

function Write-DahyeBytesAtomically {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
    [AllowNull()][byte[]]$ExpectedBytes
  )
  $fullPath = [IO.Path]::GetFullPath($Path)
  $directory = [IO.Path]::GetDirectoryName($fullPath)
  [IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = Join-Path $directory ('.{0}.{1}.{2}.tmp' -f ([IO.Path]::GetFileName($fullPath)), $PID, [guid]::NewGuid().ToString('N'))
  try {
    [IO.File]::WriteAllBytes($temporary, $Bytes)
    if ($PSBoundParameters.ContainsKey('ExpectedBytes')) {
      Assert-DahyeFileUnchanged -Path $fullPath -ExpectedBytes $ExpectedBytes
    }
    if ([IO.File]::Exists($fullPath)) {
      [IO.File]::Replace($temporary, $fullPath, $null)
    } else {
      [IO.File]::Move($temporary, $fullPath)
    }
  } finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  }
}

function Write-DahyeUtf8FileAtomically {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [AllowNull()][byte[]]$ExpectedBytes
  )
  $bytes = $script:DahyeUtf8NoBom.GetBytes($Content)
  if ($PSBoundParameters.ContainsKey('ExpectedBytes')) {
    Write-DahyeBytesAtomically -Path $Path -Bytes $bytes -ExpectedBytes $ExpectedBytes
  } else {
    Write-DahyeBytesAtomically -Path $Path -Bytes $bytes
  }
}
