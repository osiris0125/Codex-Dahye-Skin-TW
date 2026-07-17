Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$required = @(
  'README.md', 'AGENTS.md', 'LICENSE', '.github\workflows\ci.yml',
  'docs\INSTALL_WITH_CODEX.md', 'windows\assets\dahye-skin.css',
  'windows\assets\renderer-inject.js', 'windows\scripts\install-dahye-skin.ps1',
  'windows\scripts\apply-dahye-skin.ps1', 'windows\scripts\handoff-windows.ps1',
  'windows\scripts\restore-dahye-skin.ps1', 'windows\SKILL.md', 'windows\agents\openai.yaml'
)
foreach ($relative in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $repo $relative))) { throw "公開 repo 缺少：$relative" }
}

if (Test-Path -LiteralPath (Join-Path $repo 'windows\assets\dahye-hero.png')) {
  throw '公開 repo 不得提交真人海報；必須由安裝者以 -HeroPath 提供。'
}

$files = Get-ChildItem -LiteralPath $repo -Recurse -File |
  Where-Object {
    $_.FullName -notlike '*\.git\*' -and
    $_.FullName -ne $PSCommandPath -and
    $_.Extension -in '.md','.ps1','.mjs','.js','.css','.yml','.yaml','.gitignore'
  }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
foreach ($forbidden in @(
  'C:\Users\yiche', 'OneDrive\桌面', 'package-d80a3bcd67',
  '3DDF806B29CB3D782B396E0227E3E19C2180E9411CD32A93AEF62821E8D7A42D',
  'AB318BC5D3F1B63B82126A17B7A29E5C4D4A7BD7CDACEC30126B36C9A71BDAC6'
)) {
  if ($text.Contains($forbidden)) { throw "公開 repo 含單機資訊：$forbidden" }
}

$heroMentions = @(git -C $repo ls-files 2>$null | Where-Object { $_ -match '(?i)(^|/)dahye-hero\.png$' })
if ($heroMentions.Count -gt 0) { throw 'Git 索引不得包含真人海報檔。' }

$install = Get-Content -Raw -LiteralPath (Join-Path $repo 'windows\scripts\install-dahye-skin.ps1')
foreach ($token in @('HeroPath','CodexDahyeSkin','package-v1','Invoke-DahyePublicPreflight')) {
  if (-not $install.Contains($token)) { throw "通用安裝流程缺少：$token" }
}

$agent = Get-Content -Raw -LiteralPath (Join-Path $repo 'AGENTS.md')
if (-not $agent.Contains('INSTALL_WITH_CODEX.md') -or -not $agent.Contains('-HeroPath')) {
  throw 'AGENTS.md 未提供 Codex 可執行的安裝契約。'
}

$skill = Get-Content -Raw -LiteralPath (Join-Path $repo 'windows\SKILL.md')
foreach ($token in @('name: codex-dahye-skin-tw','-RestartExisting','config.toml','verify-dahye-skin.ps1')) {
  if (-not $skill.Contains($token)) { throw "Windows skill 缺少上游同等契約：$token" }
}

Write-Host 'PASS public-repository.tests.ps1'
