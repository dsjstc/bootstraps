<#
.SYNOPSIS
  Configure Windows Defender exclusions for the configs directory

.DESCRIPTION
  This script adds Windows Defender exclusions for:
  - The entire configs directory path
  - The serve-http.ps1 script
  - The bootstraps directory
  - PowerShell processes running from this location
  
  Requires Administrator privileges (UAC prompt will appear).

.PARAMETER ConfigPath
  Path to the configs directory (default: C:\Users\at\configs)

.EXAMPLE
  .\setup-defender-exclusions.ps1
  
.EXAMPLE
  .\setup-defender-exclusions.ps1 -ConfigPath "C:\MyConfigs"
#>

param(
    [string]$ConfigPath = "C:\Users\at\configs"
)

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[WARN] This script requires Administrator privileges." -ForegroundColor Yellow
    Write-Host "[INFO] Relaunching with elevation..." -ForegroundColor Gray
    
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    $startInfo.Verb = "runas"
    
    try {
        [System.Diagnostics.Process]::Start($startInfo)
        Write-Host "[INFO] Elevated PowerShell launched. Waiting for it to complete..." -ForegroundColor Gray
        exit 0
    }
    catch {
        Write-Host "[ERROR] Failed to request elevation. Please run PowerShell as Administrator." -ForegroundColor Red
        exit 1
    }
}

Write-Host "[INFO] Running with Administrator privileges" -ForegroundColor Green

# List of paths to exclude
$exclusions = @()
$exclusions += $ConfigPath
$exclusions += Join-Path $ConfigPath "bootstraps"
$exclusions += Join-Path $ConfigPath "serve-http.ps1"
$exclusions += Join-Path $ConfigPath "resource"
$exclusions += "powershell.exe"
$exclusions += "pwsh.exe"

Write-Host "`n[INFO] Checking current exclusions..." -ForegroundColor Cyan

# Get current exclusions
$currentExclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

foreach ($exclusion in $exclusions) {
    if ($currentExclusions -contains $exclusion) {
        Write-Host "[OK] Exclusion already exists: $exclusion" -ForegroundColor Green
    } else {
        Write-Host "[ADD] Adding exclusion: $exclusion" -ForegroundColor Yellow
        try {
            Add-MpPreference -ExclusionPath $exclusion -ErrorAction Stop
            Write-Host "[OK] Successfully added: $exclusion" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to add exclusion: $exclusion - $_" -ForegroundColor Red
        }
    }
}

# Also add process exclusions for PowerShell
$processExclusions = @("powershell.exe", "pwsh.exe")
$currentProcessExclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess

foreach ($process in $processExclusions) {
    if ($currentProcessExclusions -contains $process) {
        Write-Host "[OK] Process exclusion already exists: $process" -ForegroundColor Green
    } else {
        Write-Host "[ADD] Adding process exclusion: $process" -ForegroundColor Yellow
        try {
            Add-MpPreference -ExclusionProcess $process -ErrorAction Stop
            Write-Host "[OK] Successfully added: $process" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to add process exclusion: $process - $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n[INFO] Verifying exclusions..." -ForegroundColor Cyan

# Verify all exclusions are in place
$allGood = $true
foreach ($exclusion in $exclusions) {
    if ($currentExclusions -notcontains $exclusion) {
        Write-Host "[WARN] Exclusion not found: $exclusion" -ForegroundColor Yellow
        $allGood = $false
    }
}

foreach ($process in $processExclusions) {
    if ($currentProcessExclusions -notcontains $process) {
        Write-Host "[WARN] Process exclusion not found: $process" -ForegroundColor Yellow
        $allGood = $false
    }
}

if ($allGood) {
    Write-Host "`n[SUCCESS] All exclusions configured successfully!" -ForegroundColor Green
    Write-Host "[INFO] You can now run serve-http.ps1 without Defender interference." -ForegroundColor Green
} else {
    Write-Host "`n[WARN] Some exclusions could not be configured. You may need to configure them manually." -ForegroundColor Yellow
}

Write-Host "`n[INFO] To verify, run: Get-MpPreference | Select-Object ExclusionPath, ExclusionProcess" -ForegroundColor Gray
