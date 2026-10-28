# RhysCheck installer - copies the rhyscheck skill into Claude Code's personal skills folder.
# Usage (PowerShell):  irm https://raw.githubusercontent.com/Rhyyslloyd/rhyscheck/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Pin to the latest commit so a fresh push installs straight away (raw.githubusercontent.com caches 'main' for a few minutes).
$ref = 'main'
try {
    $ref = (Invoke-RestMethod -Uri 'https://api.github.com/repos/Rhyyslloyd/rhyscheck/commits/main' -Headers @{ 'User-Agent' = 'rhyscheck-installer' } -UseBasicParsing).sha
} catch { }

$base  = "https://raw.githubusercontent.com/Rhyyslloyd/rhyscheck/$ref/skills/rhyscheck"
$dest  = Join-Path $env:USERPROFILE '.claude\skills\rhyscheck'
$files = @('SKILL.md', 'scripts/checks.ps1')

New-Item -ItemType Directory -Force -Path (Join-Path $dest 'scripts') | Out-Null

foreach ($f in $files) {
    $out = Join-Path $dest ($f -replace '/', '\')
    Invoke-WebRequest -Uri "$base/$f" -OutFile $out -UseBasicParsing
    Unblock-File -Path $out
}

Write-Host ''
Write-Host "RhysCheck installed to $dest" -ForegroundColor Green
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host 'Claude Code not found. Install it first:  irm https://claude.ai/install.ps1 | iex' -ForegroundColor Yellow
} else {
    Write-Host 'Start Claude Code with:  claude'
    Write-Host 'Then run:                /rhyscheck screen flickering'
}
