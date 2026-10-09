# Release build of Stunt Track Racer VR (Windows):
#   1. Godot export templates (installed once if missing)
#   2. the headless tests (stop on a failure)
#   3. the exe (PCK embedded) with the version stamped in
#   4. build/StuntTrackRacerVR-<version>-windows.zip  (exe, start scripts, README, LICENSE)
#   5. build/StuntTrackRacerVR-<version>-setup.exe    (Inno Setup; installed once if missing)
#
#   powershell -ExecutionPolicy Bypass -File tools/build.ps1 [-Version 1.2.3] [-SkipTests] [-NoInstaller]
#
# The Godot executable comes from start.cfg (GODOT=...), as for the start
# scripts. -Version defaults to scripts/core/version.gd (release-please
# keeps it); a suffix like 1.2.3-dev is allowed (the exe's file version
# takes the numbers only).

param(
    [string]$Version = "",
    [switch]$SkipTests,
    [switch]$NoInstaller
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Build = Join-Path $Root "build"
$ExeName = "StuntTrackRacerVR.exe"

function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }

# A native program's output (stdout and stderr) as lines. Godot writes
# warnings to stderr, which PowerShell 5 would turn into errors with
# ErrorActionPreference Stop: success is judged by the result instead.
function Run([string]$exe, [string[]]$arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = & $exe @arguments 2>&1 | ForEach-Object { "$_" }
    } finally {
        $ErrorActionPreference = $old
    }
    return $lines
}

# --- Godot -------------------------------------------------------------------------
$cfg = Join-Path $Root "start.cfg"
if (-not (Test-Path $cfg)) { throw "start.cfg missing: copy start.cfg.example to start.cfg and enter the Godot path." }
$Godot = (Get-Content $cfg | Where-Object { $_ -match '^\s*GODOT\s*=' } | Select-Object -First 1) -replace '^\s*GODOT\s*=\s*', ''
if (-not $Godot -or -not (Test-Path $Godot)) { throw "Godot not found: '$Godot' (start.cfg)" }
# the console build prints to this window (and waits for Godot to finish)
$console = $Godot -replace '\.exe$', '_console.exe'
if (Test-Path $console) { $Godot = $console }
$godotVersion = (Run $Godot @("--version") | Select-Object -First 1).Trim()          # e.g. 4.7.2.stable.official.ed1daf0bf
if ($godotVersion -notmatch '^(\d+\.\d+(\.\d+)?)\.([a-z0-9]+)') { throw "Unexpected Godot version: $godotVersion" }
$godotNumber = $Matches[1]
$godotStatus = $Matches[3]
$templateDir = Join-Path $env:APPDATA "Godot\export_templates\$godotNumber.$godotStatus"
Write-Host "Godot $godotVersion"

# --- version -------------------------------------------------------------------------
if (-not $Version) {
    $line = Get-Content (Join-Path $Root "scripts\core\version.gd") | Where-Object { $_ -match 'const VERSION' }
    if ($line -notmatch '"([^"]+)"') { throw "No version in scripts/core/version.gd" }
    $Version = $Matches[1]
}
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)') { throw "Version must start with x.y.z: $Version" }
$fileVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"
Write-Host "Version $Version (file version $fileVersion)"

# --- 1. export templates ----------------------------------------------------------------
Step "Export templates"
if (Test-Path (Join-Path $templateDir "windows_release_x86_64.exe")) {
    Write-Host "installed: $templateDir"
} else {
    $tag = "$godotNumber-$godotStatus"
    $url = "https://github.com/godotengine/godot/releases/download/$tag/Godot_v${tag}_export_templates.tpz"
    $tpz = Join-Path $env:TEMP "Godot_v${tag}_export_templates.zip"
    Write-Host "downloading $url (large, once) ..."
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $url -OutFile $tpz -UseBasicParsing
    $unpack = Join-Path $env:TEMP "godot_templates_$tag"
    if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force }
    Expand-Archive -Path $tpz -DestinationPath $unpack
    New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    Copy-Item -Path (Join-Path $unpack "templates\*") -Destination $templateDir -Recurse -Force
    Remove-Item $unpack -Recurse -Force
    Remove-Item $tpz -Force
    Write-Host "installed: $templateDir"
}

# --- 2. tests ------------------------------------------------------------------------------
Run $Godot @("--headless", "--xr-mode", "off", "--path", $Root, "--import") | Out-Null
if (-not $SkipTests) {
    Step "Tests"
    $out = Run $Godot @("--headless", "--xr-mode", "off", "--path", $Root, "--script", "res://tests/run_tests.gd")
    $out | Where-Object { $_ -match 'FAIL|passed' } | ForEach-Object { Write-Host $_ }
    $summary = $out | Where-Object { $_ -match '(\d+) passed, (\d+) failed' } | Select-Object -Last 1
    if (-not $summary -or $summary -notmatch ', 0 failed') { throw "Tests failed - no build." }
}

# --- 3. export ------------------------------------------------------------------------------
Step "Export"
New-Item -ItemType Directory -Force -Path $Build | Out-Null
$presets = Join-Path $Root "export_presets.cfg"
$presetsText = Get-Content $presets -Raw
try {
    # the version into the exe's properties (for this export only)
    $stamped = $presetsText -replace 'application/file_version="[^"]*"', "application/file_version=`"$fileVersion`"" `
                            -replace 'application/product_version="[^"]*"', "application/product_version=`"$fileVersion`""
    [IO.File]::WriteAllText($presets, $stamped)
    $exe = Join-Path $Build $ExeName
    if (Test-Path $exe) { Remove-Item $exe -Force }
    Run $Godot @("--headless", "--path", $Root, "--export-release", "Windows Desktop", $exe) | Where-Object { $_ -match 'ERROR' } | ForEach-Object { Write-Host $_ }
    if (-not (Test-Path $exe)) { throw "Export failed: no $exe" }
} finally {
    [IO.File]::WriteAllText($presets, $presetsText)
}
Write-Host ("exe: {0} ({1:N1} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))

# --- 4. zip ----------------------------------------------------------------------------------
Step "ZIP"
$package = Join-Path $Build "package"
if (Test-Path $package) { Remove-Item $package -Recurse -Force }
New-Item -ItemType Directory -Force -Path $package | Out-Null
Copy-Item $exe $package
Copy-Item (Join-Path $PSScriptRoot "release\*.cmd") $package
Copy-Item (Join-Path $Root "README.md"), (Join-Path $Root "README.de.md"), (Join-Path $Root "LICENSE") $package
$zip = Join-Path $Build "StuntTrackRacerVR-$Version-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $zip
Write-Host "zip: $zip"

# --- 5. installer -------------------------------------------------------------------------------
if (-not $NoInstaller) {
    Step "Installer"
    $iscc = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) {
        Write-Host "Inno Setup not found: installing it once (winget) ..."
        winget install --id JRSoftware.InnoSetup -e --silent --scope user --accept-package-agreements --accept-source-agreements | Out-Host
        if ($LASTEXITCODE -ne 0) {
            winget install --id JRSoftware.InnoSetup -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
        }
        $iscc = @(
            (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
            (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
            (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $iscc) { throw "Inno Setup could not be installed (ISCC.exe not found)." }
    }
    $isccOut = Run $iscc @("/DAppVersion=$Version", "/DFileVersion=$fileVersion", "/DSourceDir=$package", "/DOutputDir=$Build", (Join-Path $PSScriptRoot "installer.iss"))
    if ($LASTEXITCODE -ne 0) { $isccOut | Select-Object -Last 15 | ForEach-Object { Write-Host $_ }; throw "Inno Setup failed ($LASTEXITCODE)." }
    $setup = Join-Path $Build "StuntTrackRacerVR-$Version-setup.exe"
    Write-Host "installer: $setup"
}

Step "Done: $Version"
Get-ChildItem $Build -File | Where-Object { $_.Name -like "*$Version*" -or $_.Name -eq $ExeName } | ForEach-Object { Write-Host ("  {0}  ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB)) }
