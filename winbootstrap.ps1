<# bootstrap.ps1 - Windows Config Bootstrap Script
#####################################################
Run with:

iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/main/bootstrap.ps1 | iex

#>

param(
    [string]$ConfigPath = "C:\Users\$env:USERNAME\windev\configs",
    [string]$BitwardenItem = "github-ssh-key",
    [switch]$SkipSetup
)

$ErrorActionPreference = "Continue"

# === Helpers ===
function Write-Header { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Step   { param([int]$n, [string]$m) Write-Host "`n[$n/4] $m" -ForegroundColor Yellow }
function Write-Ok     { param([string]$m) Write-Host "  OK: $m" -ForegroundColor Green }
function Write-Fail   { param([string]$m) Write-Host "  ERROR: $m" -ForegroundColor Red }
function Write-Info   { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }

# === Spinner ===
function Wait-ForCondition {
    param(
        [scriptblock]$Condition,
        [string]$Message,
        [int]$TimeoutSeconds = 300
    )
    $spinner = @('|','/','-','\')
    $i = 0
    $elapsed = 0
    while (-not (& $Condition)) {
        $s = $spinner[$i % 4]
        Write-Host "`r  $s $Message ($elapsed s)   " -NoNewline
        Start-Sleep -Seconds 1
        $i++
        $elapsed++
        if ($elapsed -ge $TimeoutSeconds) {
            Write-Host ""
            Write-Fail "Timed out after $TimeoutSeconds seconds."
            return $false
        }
    }
    Write-Host "`r  OK: $Message                    "
    return $true
}

# === SSH Agent Check ===
function Test-SshAgentHasKey {
    $result = ssh-add -l 2>&1
    return ($LASTEXITCODE -eq 0 -and $result -notmatch "no identities")
}

Write-Header "Windows Config Bootstrap"

# === Step 1: GitHub Username ===
Write-Step 1 "GitHub username"
$GitHubUser = Read-Host "Enter your GitHub username"
if ([string]::IsNullOrWhiteSpace($GitHubUser)) {
    Write-Fail "GitHub username is required. Exiting."
    exit 1
}
$ConfigRepo = "git@github.com:${GitHubUser}/configs.git"

# === Step 2: Install Prerequisites ===
Write-Step 2 "Installing prerequisites"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail "winget not found. Update 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Info "Installing Git..."
    winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Fail "Git install failed. Exiting."
        exit 1
    }
    Write-Ok "Git installed."
} else {
    Write-Ok "Git already installed."
}

if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Info "Installing Bitwarden desktop..."
    winget install --id Bitwarden.Bitwarden -e --silent --accept-source-agreements --accept-package-agreements
    Write-Ok "Bitwarden installed."
} else {
    Write-Ok "Bitwarden already installed."
}

# === Step 3: Wait for Bitwarden SSH Agent ===
Write-Step 3 "Bitwarden SSH agent"

if (-not (Test-SshAgentHasKey)) {
    Write-Host ""
    Write-Host "  Action required:" -ForegroundColor Yellow
    Write-Host "    1. Launch Bitwarden" -ForegroundColor Yellow
    Write-Host "    2. Log in and unlock your vault" -ForegroundColor Yellow
    Write-Host "    3. Settings -> SSH Agent -> Enable" -ForegroundColor Yellow
    Write-Host "    4. Ensure at least one SSH key is in your vault" -ForegroundColor Yellow
    Write-Host ""

    $ok = Wait-ForCondition -Condition { Test-SshAgentHasKey } -Message "Waiting for SSH key via Bitwarden agent"
    if (-not $ok) { exit 1 }
}
Write-Ok "SSH agent has key(s) loaded."

# === Step 4: Clone/Update Configs Repo ===
Write-Step 4 "Fetching configs repository"

$parentPath = Split-Path $ConfigPath
if (-not (Test-Path $parentPath)) {
    New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
}

if (-not (Test-Path $ConfigPath)) {
    Write-Info "Cloning $ConfigRepo ..."
    git clone $ConfigRepo $ConfigPath
    if ($LASTEXITCODE -ne 0) { Write-Fail "Clone failed."; exit 1 }
    Write-Ok "Repository cloned."
} else {
    Write-Info "Repo exists, pulling updates..."
    Push-Location $ConfigPath
    $status = git -C $ConfigPath status --porcelain
    if ($status) {
        Write-Fail "configs/ has uncommitted changes. Stash or commit first."
        exit 1
    }
    git fetch --all
    git pull --rebase
    Pop-Location
    Write-Ok "Repository updated."
}

# === Run setup.ps1 ===
if (-not $SkipSetup) {
    Write-Header "Running setup script"
    $SetupScript = Join-Path $ConfigPath "newpc\setup.ps1"
    if (Test-Path $SetupScript) {
        & $SetupScript
        Write-Ok "setup.ps1 completed."
    } else {
        Write-Fail "setup.ps1 not found at $SetupScript — run it manually."
    }
}

Write-Header "Bootstrap Complete"
Write-Host "Configs: $ConfigPath" -ForegroundColor Cyan