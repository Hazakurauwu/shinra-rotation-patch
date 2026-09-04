# Self-elevate to admin (ShinraMeter may live under Program Files).
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`""
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms

# See install.ps1 for why: the classic FolderBrowserDialog has no address
# bar at all, so a pasted path can't be used -- this is the standard
# workaround (Explorer-style OpenFileDialog in folder-pick mode).
function Select-FolderDialog {
    param([string]$description = "Select a folder")
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $description
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.FileName = "Select Folder"
    $dlg.Filter = "Folders|`n"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return [System.IO.Path]::GetDirectoryName($dlg.FileName)
}

function Find-PatchedFolder {
    param([string]$base)
    if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path $base)) { return $null }
    $hits = Get-ChildItem -Path $base -Filter "DamageMeter.dll.prepatch.bak" -Recurse -File -ErrorAction SilentlyContinue
    if (-not $hits) { return $null }
    $pref = $hits | Where-Object { $_.Directory.Name -ieq "ShinraMeter" } | Select-Object -First 1
    if ($pref) { return $pref.Directory.FullName }
    return $hits[0].Directory.FullName
}

# Process-name checks only catch clients literally called
# TeraToolbox/tera-toolbox -- Crazy-eSports-ClassicPlus runs under totally
# different process names, so that check silently never fired for it.
# Probing the file itself works regardless of what the launcher is named.
function Test-FileLocked {
    param([string]$path)
    if (-not (Test-Path $path)) { return $false }
    try {
        $s = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $s.Close()
        return $false
    } catch { return $true }
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   ShinraMeter Rotation Patch - Uninstaller" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

$common = @(
    "$env:USERPROFILE\Desktop\TeraToolbox","$env:USERPROFILE\Desktop\TeraToolbox Private",
    "$env:USERPROFILE\Documents\TeraToolbox","$env:USERPROFILE\Downloads\TeraToolbox",
    "${env:ProgramFiles(x86)}\TeraToolbox","$env:ProgramFiles\TeraToolbox",
    "C:\TeraToolbox","C:\TeraToolbox Private","D:\TeraToolbox",
    "$env:APPDATA","$env:LOCALAPPDATA"
)
$shinra = $null
foreach ($c in $common) { $shinra = Find-PatchedFolder $c; if ($shinra) { break } }

if ($shinra) {
    Write-Host "  Found patched ShinraMeter at:" -ForegroundColor Cyan
    Write-Host "    $shinra"; Write-Host ""
    $ans = Read-Host "  Restore this folder? Press Enter for yes, or type N to choose another"
    if ($ans -match '^[nN]') { $shinra = $null }
}
if (-not $shinra) {
    Write-Host "  A window will open. Type or paste the folder path and press Enter, or browse to it." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 400
    while (-not $shinra) {
        $selected = Select-FolderDialog "Select your TeraToolbox folder (or the ShinraMeter folder)"
        if (-not $selected) {
            Write-Host "  Cancelled. Nothing was changed." -ForegroundColor Red
            Read-Host "  Press Enter to exit"; exit 1
        }
        $shinra = Find-PatchedFolder $selected
        if (-not $shinra) { Write-Host "  No backup found there. Try again." -ForegroundColor Red }
    }
    Write-Host "  Using: $shinra" -ForegroundColor Cyan
}

if (Test-FileLocked (Join-Path $shinra "DamageMeter.dll")) {
    Write-Host ""
    Write-Host "  The client still has DamageMeter.dll open. Close it, then press Enter." -ForegroundColor Yellow
    Read-Host
}

Write-Host ""
Write-Host "  Restoring original files..."
try {
    foreach ($f in @("DamageMeter.dll","module.json","manifest.json")) {
        $bak = Join-Path $shinra "$f.prepatch.bak"
        if (Test-Path $bak) { Copy-Item $bak (Join-Path $shinra $f) -Force -ErrorAction Stop; Write-Host "    restored: $f" }
    }
} catch {
    Write-Host ""
    if ($_.Exception.Message -match "being used|another process|in use") {
        Write-Host "  TeraToolbox is still open. Close it and run this again." -ForegroundColor Red
    } else { Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "  Press Enter to exit"; exit 1
}

$rot = Join-Path $shinra "ShinraRotationPatch.dll"
if (Test-Path $rot) { Remove-Item $rot -Force; Write-Host "    removed: ShinraRotationPatch.dll" }

foreach ($f in @("DamageMeter.dll","module.json","manifest.json")) {
    $bak = Join-Path $shinra "$f.prepatch.bak"
    if (Test-Path $bak) { Remove-Item $bak -Force }
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   Done! Your ShinraMeter is back to normal." -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Read-Host "  Press Enter to exit"
