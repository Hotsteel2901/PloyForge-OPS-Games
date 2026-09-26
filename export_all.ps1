#Requires -Version 5.1
# One-click export script for PolyForge: Ops (Windows PowerShell)
# Usage:
#   .\export_all.ps1
#   .\export_all.ps1 -Godot "C:\Path\To\Godot_v4.x-stable_win64.exe"
param(
    [string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Test-Godot {
    $cmd = Get-Command $Godot -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Error @"
Godot not found: $Godot
Download the matching export templates from the Godot editor
(Editor -> Manage Export Templates) or set the path explicitly:
  .\export_all.ps1 -Godot "C:\Path\To\godot.exe"
"@
        exit 1
    }
}

function Export-Platform($preset, $out) {
    $dir = Split-Path -Parent (Join-Path $root $out)
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-Host "Exporting $preset -> $out ..." -ForegroundColor Cyan
    & $Godot --headless --path $root --export-release $preset (Join-Path $root $out)
    if ($LASTEXITCODE -ne 0) {
        throw "Export failed for $preset (exit code $LASTEXITCODE)"
    }
    Write-Host "  OK: $out" -ForegroundColor Green
}

Test-Godot
Export-Platform "Windows Desktop" "build/windows/PolyForgeOps.exe"
Export-Platform "Linux"           "build/linux/PolyForgeOps.x86_64"
Export-Platform "Web"             "build/web/index.html"

Write-Host "`nAll exports complete." -ForegroundColor Green
Write-Host "Linux binary needs executable permission on target machine:"
Write-Host "  chmod +x build/linux/PolyForgeOps.x86_64"
Write-Host "Web build must be served over HTTP (not file://):"
Write-Host "  cd build/web && python -m http.server 8000"
