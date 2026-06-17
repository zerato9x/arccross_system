param(
    [switch]$Rebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GodotCandidates = @(
    (Get-Command godot -ErrorAction SilentlyContinue).Source,
    (Get-Command godot4 -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.6-stable_win64.exe",
    "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.6.3-stable_win64.exe",
    'C:\Program Files\Godot\Godot_v4.6-stable_win64.exe'
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $GodotCandidates) {
    throw 'Godot executable not found. Add Godot 4.6 to PATH or install it locally.'
}

$GodotExe = $GodotCandidates
Write-Host "Building macro hex TileSet with: $GodotExe"
& $GodotExe --headless --path $ProjectRoot --script res://Tools/Build-HexTileSet.gd
if ($LASTEXITCODE -ne 0) {
    throw "Build-HexTileSet failed with exit code $LASTEXITCODE."
}

Write-Host 'MacroTileSet.tres and MacroTileCatalog.tres are ready under Asset/.'
