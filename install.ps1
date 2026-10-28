# RhysCheck installer - copies the rhyscheck skill into Claude Code's personal skills folder.
# Usage (PowerShell):  irm https://raw.githubusercontent.com/Rhyyslloyd/rhyscheck/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$base  = 'https://raw.githubusercontent.com/Rhyyslloyd/rhyscheck/main/skills/rhyscheck'
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
