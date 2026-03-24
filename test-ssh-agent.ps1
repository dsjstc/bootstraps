# Test script for SSH Agent detection
# This script tests various methods to detect Bitwarden SSH agent

$ErrorActionPreference = "Continue"

function Write-Header { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Step   { param([int]$n, [string]$m) Write-Host "`n[$n] $m" -ForegroundColor Yellow }
function Write-Ok     { param([string]$m) Write-Host "  OK: $m" -ForegroundColor Green }
function Write-Fail   { param([string]$m) Write-Host "  ERROR: $m" -ForegroundColor Red }
function Write-Info   { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }

Write-Header "SSH Agent Detection Tests"

# Test 1: Check if Bitwarden process is running
Write-Step 1 "Bitwarden Process Check"
$bwProcess = Get-Process -Name "Bitwarden" -ErrorAction SilentlyContinue
if ($bwProcess) {
    Write-Ok "Bitwarden process found (PID: $($bwProcess.Id))"
    Write-Info "MainWindowTitle: $($bwProcess.MainWindowTitle)"
} else {
    Write-Fail "Bitwarden process not found"
}

# Test 2: Check for ssh-agent processes
Write-Step 2 "SSH Agent Processes"
$sshProcesses = Get-Process -Name "ssh-*", "pageant", "winssh-*" -ErrorAction SilentlyContinue
if ($sshProcesses) {
    Write-Ok "SSH agent processes found:"
    foreach ($p in $sshProcesses) {
        Write-Info "  - $($p.ProcessName) (PID: $($p.Id))"
    }
} else {
    Write-Info "No dedicated SSH agent processes found"
}

# Test 3: Check SSH_AUTH_SOCK environment variable
Write-Step 3 "SSH_AUTH_SOCK Environment Variable"
if ($env:SSH_AUTH_SOCK) {
    Write-Ok "SSH_AUTH_SOCK is set: $env:SSH_AUTH_SOCK"
    if (Test-Path $env:SSH_AUTH_SOCK) {
        Write-Ok "Socket file exists"
    } else {
        Write-Fail "Socket file does not exist"
    }
} else {
    Write-Info "SSH_AUTH_SOCK is not set"
}

# Test 4: Try ssh-add -l
Write-Step 4 "ssh-add -l Command"
try {
    $result = & ssh-add -l 2>&1
    Write-Ok "ssh-add -l output:"
    Write-Info "  $result"
} catch {
    Write-Fail "ssh-add -l failed: $_"
}

# Test 5: Check for Bitwarden SSH socket files
Write-Step 5 "Bitwarden SSH Socket Files"
$bwInstallPath = "C:\Users\$env:USERNAME\AppData\Local\Programs\Bitwarden"
if (Test-Path $bwInstallPath) {
    Write-Info "Searching in: $bwInstallPath"
    $socketFiles = Get-ChildItem -Path $bwInstallPath -Recurse -Filter "*ssh*" -ErrorAction SilentlyContinue
    if ($socketFiles) {
        Write-Ok "Found SSH-related files:"
        foreach ($f in $socketFiles) {
            Write-Info "  - $($f.FullName)"
        }
    } else {
        Write-Info "No SSH-related files found in Bitwarden install"
    }
} else {
    Write-Fail "Bitwarden install path not found: $bwInstallPath"
}

# Test 6: Check for socket directory
Write-Step 6 "Socket Directory Check"
$socketDir = "C:\Users\$env:USERNAME\AppData\Local\Bitwarden"
if (Test-Path $socketDir) {
    Write-Info "Checking: $socketDir"
    $sockets = Get-ChildItem -Path $socketDir -Recurse -Filter "*.sock" -ErrorAction SilentlyContinue
    if ($sockets) {
        Write-Ok "Found socket files:"
        foreach ($s in $sockets) {
            Write-Info "  - $($s.FullName)"
        }
    } else {
        Write-Info "No .sock files found"
    }
} else {
    Write-Info "Socket directory not found: $socketDir"
}

# Test 7: Check Bitwarden CLI installation
Write-Step 7 "Bitwarden CLI Check"
$bwCliPath = "C:\Users\$env:USERNAME\AppData\Local\Bitwarden\cli"
if (Test-Path $bwCliPath) {
    Write-Ok "Bitwarden CLI path exists: $bwCliPath"
    $bwExe = Get-ChildItem -Path $bwCliPath -Filter "bw.exe" -ErrorAction SilentlyContinue
    if ($bwExe) {
        Write-Ok "bw.exe found: $($bwExe.FullName)"
    }
} else {
    Write-Info "Bitwarden CLI path not found: $bwCliPath"
}

# Test 8: Check for Bitwarden SSH agent configuration
Write-Step 8 "Bitwarden SSH Agent Configuration"
$bwConfigPath = "C:\Users\$env:USERNAME\AppData\Local\Bitwarden\config.json"
if (Test-Path $bwConfigPath) {
    Write-Ok "Config file found: $bwConfigPath"
    try {
        $config = Get-Content $bwConfigPath -Raw | ConvertFrom-Json
        Write-Info "Config content:"
        $config | Format-List | Out-String | ForEach-Object { Write-Info "  $_" }
    } catch {
        Write-Fail "Failed to read config: $_"
    }
} else {
    Write-Info "Config file not found: $bwConfigPath"
}

Write-Header "SSH Agent Detection Complete"
