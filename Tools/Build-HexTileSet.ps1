param(
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GodotCandidates = @(
    'C:\Users\zerat\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe',
    "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.1-stable_win64.exe",
    'C:\Program Files\Godot\Godot_v4.7.1-stable_win64.exe'
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $GodotCandidates) {
    throw 'Godot 4.7.1 executable not found. Install the approved Godot 4.7.1 client locally.'
}

$GodotExe = $GodotCandidates
Write-Host "Building macro hex TileSet with: $GodotExe"
& $GodotExe --headless --path $ProjectRoot --script res://Tools/Build-HexTileSet.gd
if ($LASTEXITCODE -ne 0) {
    throw "Build-HexTileSet failed with exit code $LASTEXITCODE."
}

Write-Host 'MacroTileSet.tres and MacroTileCatalog.tres are ready under Asset/.'
