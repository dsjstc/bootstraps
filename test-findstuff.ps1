# Test script for FindStuff functionality
# This script defines the necessary functions and runs Test-FindStuff

$ErrorActionPreference = "Continue"

# Refresh PATH to ensure newly installed tools are available
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH","User")

# === Helpers ===
function Write-Header { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Step   { param([int]$n, [string]$m) Write-Host "`n[$n/4] $m" -ForegroundColor Yellow }
function Write-Ok     { param([string]$m) Write-Host "  OK: $m" -ForegroundColor Green }
function Write-Fail   { param([string]$m) Write-Host "  ERROR: $m" -ForegroundColor Red }
function Write-Info   { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }

# === FindStuff Subroutine ===
function Test-FindStuff {
    Write-Header "FindStuff Check"
    $allPassed = $true
    
    # Add Git bin directory to PATH if it exists
    $gitBinPath = "C:\Program Files\Git\bin"
    if (Test-Path $gitBinPath) {
        if ($env:PATH -notlike "*$gitBinPath*") {
            $env:PATH = "$gitBinPath;$env:PATH"
        }
    }
    
    # Check Git
    Write-Step 1 "Git"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = git --version
        Write-Ok "Git found: $gitVersion"
    } else {
        Write-Fail "Git not found"
        $allPassed = $false
    }
    
    # Check Bitwarden desktop
    Write-Step 2 "Bitwarden"
    $bwPath = "C:\Users\$env:USERNAME\AppData\Local\Programs\Bitwarden\Bitwarden.exe"
    if (Test-Path $bwPath) {
        Write-Ok "Bitwarden desktop found: $bwPath"
    } else {
        Write-Fail "Bitwarden desktop not found"
        $allPassed = $false
    }
    
    # Check configs directory
    Write-Step 3 "Configs directory"
    $configsPath = "C:\Users\$env:USERNAME\windev\configs"
    if (Test-Path $configsPath) {
        Write-Ok "Configs directory exists: $configsPath"
    } else {
        Write-Fail "Configs directory not found: $configsPath"
        $allPassed = $false
    }
    
    Write-Header "FindStuff Complete"
    if ($allPassed) {
        Write-Ok "All checks passed."
        return 0
    } else {
        Write-Fail "Some checks failed."
        return 1
    }
}

# Run Test-FindStuff
exit Test-FindStuff
