<#
bootstrap.ps1 - Windows Config Bootstrap Script
#####################################################
v1.0. Bootstrap with .env unlock, SSH key fetch, and GitHub auth.

Run with:
.\winbootstrap.ps1
#>

param(
    [string]$ConfigPath,
    [switch]$SkipSetup,
    [switch]$FindStuff,
    [switch]$CheckSsh,
    [switch]$TestMode
)

# Set default ConfigPath if not provided (user confirmed ~/configs is correct)
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = "C:\Users\$env:USERNAME\configs"
}

$ErrorActionPreference = "Continue"

# === Logging Setup ===
$LogDir = Join-Path $env:TEMP "winbootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir "winbootstrap.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    if ($Level -eq "ERROR") {
        Write-Host $logEntry -ForegroundColor Red
    } elseif ($Level -eq "WARN") {
        Write-Host $logEntry -ForegroundColor Yellow
    } else {
        Write-Host $logEntry -ForegroundColor Gray
    }
}

# === Helpers ===
function Write-Header { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan; Write-Log "=== $m ===" }
function Write-Step   { param([int]$n, [string]$m) Write-Host ("[{0}/4] {1}" -f $n, $m) -ForegroundColor Yellow; Write-Log ("Step {0}: {1}" -f $n, $m) }
function Write-Ok     { param([string]$m) Write-Host "  OK: $m" -ForegroundColor Green; Write-Log "OK: $m" }
function Write-Fail   { param([string]$m) Write-Host "  ERROR: $m" -ForegroundColor Red; Write-Log "ERROR: $m" -Level "ERROR" }
function Write-Info   { param([string]$m) Write-Host "  $m" -ForegroundColor Gray; Write-Log "INFO: $m" }
function Write-Warn   { param([string]$m) Write-Host "  WARN: $m" -ForegroundColor Yellow; Write-Log "WARN: $m" -Level "WARN" }

# === Get Dev Machine IP ===
function Get-DevMachineIP {
    # Get local IP address for LAN access
    $ipAddress = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "127.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress
    
    if (-not $ipAddress) {
        $ipAddress = "192.168.3.200"  # Default fallback
    }
    
    return $ipAddress
}

# === Pause Function ===
function Write-Pause {
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

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

# === .env File Loading (after Write-Log is defined) ===
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Write-Log "Loading .env file from $envFile" -Level "INFO"
    Get-Content $envFile | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or $_.TrimStart().StartsWith('#')) {
            return
        }
        if ($_ -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($key, $value, 'Process')
            Write-Log "Loaded env var: $key" -Level "INFO"
        }
    }
}

# === SSH Key Fetch Function ===
function Invoke-BwSshKeyFetch {
    Write-Header "Fetching SSH Key from Bitwarden"
    Write-Log "Starting SSH key fetch" -Level "INFO"
    
    # Check if bw command is available
    $bwCmd = Get-Command bw -ErrorAction SilentlyContinue
    if (-not $bwCmd) {
        Write-Warn "Bitwarden CLI not found in PATH. SSH key fetch skipped."
        Write-Log "Bitwarden CLI not found in PATH" -Level "WARN"
        return $false
    }
    
    # Check if vault is unlocked (use BW_SESSION environment variable)
    if ($env:BW_SESSION) {
        Write-Log "Using BW_SESSION environment variable" -Level "INFO"
        $env:BW_SESSION = $env:BW_SESSION
    }
    
    $bwStatus = bw status 2>&1
    if ($bwStatus -match '"status":"locked"') {
        Write-Warn "Bitwarden vault is locked. Cannot fetch SSH key."
        Write-Log "Vault is locked" -Level "WARN"
        return $false
    }
    
    if ($bwStatus -match '"status":"unlocked"') {
        Write-Log "Vault is already unlocked" -Level "INFO"
    }
    
    # List all items and find SSH keys with "github" in notes
    Write-Log "Listing Bitwarden items..." -Level "INFO"
    $allItems = bw list items 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to list Bitwarden items"
        Write-Log "Failed to list items: $allItems" -Level "ERROR"
        return $false
    }
    
    $itemsJson = $allItems | ConvertFrom-Json
    $sshKeyItem = $null
    
    foreach ($item in $itemsJson) {
        if ($item.type -eq 5) {  # SSH Key type
            $notes = $item.notes -join "`n"
            if ($notes -match 'github') {
                $sshKeyItem = $item
                Write-Ok "Found SSH key: $($item.name) (ID: $($item.id))"
                Write-Log "Found SSH key: $($item.name)" -Level "INFO"
                break
            }
        }
    }
    
    if (-not $sshKeyItem) {
        Write-Fail "No SSH key with 'github' in notes found"
        Write-Log "No SSH key with github in notes" -Level "ERROR"
        return $false
    }
    
    # Extract private key
    Write-Log "Extracting private key..." -Level "INFO"
    if (-not $sshKeyItem.sshkey) {
        Write-Fail "No sshkey object found in item"
        Write-Log "No sshkey object" -Level "ERROR"
        return $false
    }
    
    $privateKey = $sshKeyItem.sshkey.privateKey
    if (-not $privateKey) {
        Write-Fail "No private key found in item"
        Write-Log "No privateKey found" -Level "ERROR"
        return $false
    }
    
    Write-Log "Private key length: $($privateKey.Length) characters" -Level "INFO"
    
    # Write to ~/.ssh/id_github without BOM
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $sshDir)) {
        Write-Info "Creating .ssh directory..."
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    
    $keyFile = Join-Path $sshDir "id_github"
    # Write without BOM (UTF8 encoding with BOM causes SSH to reject the key)
    [System.Text.UTF8Encoding]::new($false).GetString([System.Text.Encoding]::UTF8.GetBytes($privateKey)) | Set-Content -Path $keyFile -NoNewline
    Write-Ok "Written to: $keyFile"
    Write-Log "SSH key written to $keyFile" -Level "INFO"
    
    # Set GIT_SSH_COMMAND environment variable
    $env:GIT_SSH_COMMAND = "ssh -i $keyFile"
    Write-Ok "Set GIT_SSH_COMMAND to use $keyFile"
    Write-Log "GIT_SSH_COMMAND set" -Level "INFO"
    
    return $true
}

# === Bitwarden Authentication Function ===
function Start-BwAuth {
    Write-Header "Bitwarden Authentication"
    Write-Log "Starting Bitwarden authentication" -Level "INFO"
    
    # Check if already logged in and unlocked
    $bwStatus = bw status 2>&1
    if ($bwStatus -match '"status":"unlocked"') {
        Write-Ok "Already logged in to Bitwarden"
        Write-Log "Bitwarden already authenticated" -Level "INFO"
        return $true
    }
    
    # Check if vault is locked (logged in but needs unlock)
    if ($bwStatus -match '"status":"locked"') {
        Write-Info "Bitwarden vault is locked. Unlocking..." -ForegroundColor Yellow
        Write-Log "Vault is locked, prompting for unlock" -Level "INFO"
        
        # Check for BW_MASTER_PW from .env file or environment
        if ($env:BW_MASTER_PW) {
            Write-Info "Using BW_MASTER_PW from environment..." -ForegroundColor Gray
            Write-Log "Using BW_MASTER_PW env var for unlock" -Level "INFO"
            $unlockResult = bw unlock --passwordenv BW_MASTER_PW 2>&1
            if ($LASTEXITCODE -eq 0) {
                # Extract session key from output using regex
                $pattern = 'BW_SESSION="([^"]+)"'
                $match = [regex]::Match($unlockResult, $pattern)
                if ($match.Success) {
                    $sessionKey = $match.Groups[1].Value
                    [Environment]::SetEnvironmentVariable('BW_SESSION', $sessionKey, 'Process')
                    Write-Log "Set BW_SESSION environment variable" -Level "INFO"
                }
                Write-Ok "Vault unlocked successfully"
                Write-Log "Vault unlocked using BW_MASTER_PW" -Level "INFO"
                return $true
            } else {
                Write-Fail "Failed to unlock with BW_MASTER_PW"
                Write-Log "Vault unlock failed with BW_MASTER_PW: $unlockResult" -Level "ERROR"
                return $false
            }
        }
        
        # No password available - fail without prompting
        Write-Fail "BW_MASTER_PW environment variable not set. Cannot unlock vault without prompting."
        Write-Log "Vault unlock failed: BW_MASTER_PW not set" -Level "ERROR"
        return $false
    }
    
    # Not logged in at all
    Write-Info "Not logged in to Bitwarden. Please login manually." -ForegroundColor Yellow
    Write-Log "Not logged in" -Level "INFO"
    return $false
}

# === FindStuff Subroutine ===
function Test-FindStuff {
    Write-Header "FindStuff Check"
    $allPassed = $true
    
    # Check Git
    Write-Step 1 "Git"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = git --version
        Write-Ok "Git found: $gitVersion"
    } else {
        Write-Fail "Git not found"
        $allPassed = $false
    }
    
    # Check Bitwarden CLI
    Write-Step 2 "Bitwarden CLI"
    if (Get-Command bw -ErrorAction SilentlyContinue) {
        $bwVersion = bw --version
        Write-Ok "Bitwarden CLI found: $bwVersion"
    } else {
        Write-Info "Bitwarden CLI not found (will be installed)"
    }
    
    # Check configs directory
    Write-Step 3 "Configs directory"
    $configsPath = "C:\Users\$env:USERNAME\configs"
    if (Test-Path $configsPath) {
        Write-Ok "Configs directory exists: $configsPath"
    } else {
        Write-Info "Configs directory not found (will be created)"
    }
    
    # Check SSH key
    Write-Step 4 "SSH key"
    $sshKey = Join-Path $env:USERPROFILE ".ssh\id_github"
    if (Test-Path $sshKey) {
        Write-Ok "SSH key found: $sshKey"
    } else {
        Write-Info "SSH key not found (will be fetched)"
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

# === Main Bootstrap Logic ===
function Invoke-Bootstrap {
    Write-Header "Windows Config Bootstrap"
    
    # === Step 1: GitHub Username ===
    Write-Step 1 "GitHub username"
    $GitHubUser = "dsjstc"
    $ConfigRepo = "git@github.com:${GitHubUser}/configs.git"
    
    # === Step 2: Install Prerequisites ===
    Write-Step 2 "Installing prerequisites"
    
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail "winget not found. Update 'App Installer' from the Microsoft Store, then re-run."
        Write-Pause
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
            Write-Pause
            exit 1
        }
        Write-Ok "Git installed."
    } else {
        Write-Ok "Git already installed."
    }
    
    # Install Bitwarden CLI
    $bwCmd = Get-Command bw -ErrorAction SilentlyContinue
    if (-not $bwCmd) {
        Write-Info "Installing Bitwarden CLI..."
        winget install --id Bitwarden.CLI -e --silent --accept-source-agreements --accept-package-agreements
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
        if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
            Write-Warn "Bitwarden CLI install may have failed. Continuing anyway."
        } else {
            Write-Ok "Bitwarden CLI installed."
        }
    } else {
        Write-Ok "Bitwarden CLI already installed."
    }
    
    # === Step 3: Bitwarden Authentication ===
    Write-Step 3 "Bitwarden authentication"
    
    if (-not (Start-BwAuth)) {
        Write-Fail "Bitwarden authentication failed. Exiting."
        Write-Pause
        exit 1
    }
    
    # === Step 4: Fetch SSH Key ===
    Write-Step 4 "Fetching SSH key"
    
    if (-not (Invoke-BwSshKeyFetch)) {
        Write-Warn "SSH key fetch failed. GitHub operations may fail."
        Write-Log "SSH key fetch failed" -Level "WARN"
    }
    
    # === Step 5: Clone/Update Configs Repo ===
    Write-Header "Fetching configs repository"
    
    $parentPath = Split-Path $ConfigPath
    if (-not (Test-Path $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
    
    # TestMode: Use a public test repo instead of configs
    $TestRepo = "https://github.com/octocat/Hello-World.git"
    $TestPath = "C:\Users\$env:USERNAME\test-repo"
    
    if (-not (Test-Path $ConfigPath)) {
        if ($TestMode) {
            Write-Info "TestMode: Cloning test repo $TestRepo to $TestPath ..."
            git clone $TestRepo $TestPath
            if ($LASTEXITCODE -ne 0) { Write-Fail "Clone failed."; Write-Pause; exit 1 }
            Write-Ok "Test repository cloned."
        } else {
            Write-Info "Cloning $ConfigRepo ..."
            git clone $ConfigRepo $ConfigPath
            if ($LASTEXITCODE -ne 0) { Write-Fail "Clone failed."; Write-Pause; exit 1 }
            Write-Ok "Repository cloned."
        }
    } else {
        Write-Info "Repo exists, checking for updates..."
        Push-Location $ConfigPath
        $status = git -C $ConfigPath status --porcelain
        if ($status) {
            Write-Warn "configs/ has uncommitted changes. Skipping pull (dev environment)."
            Write-Log "Skipping git pull due to uncommitted changes" -Level "WARN"
        } else {
            Write-Info "Pulling updates..."
            git fetch --all
            git pull --rebase
            Write-Ok "Repository updated."
        }
        Pop-Location
    }
    
    # === Run setup.ps1 ===
    if (-not $SkipSetup) {
        Write-Header "Running setup script"
        $SetupScript = Join-Path $ConfigPath "newpc\setup.ps1"
        if (Test-Path $SetupScript) {
            Write-Log "Running setup.ps1 with -Option0 (exit immediately)" -Level "INFO"
            $setupExitCode = & $SetupScript -Option0
            Write-Log "setup.ps1 exited with code: $setupExitCode" -Level "INFO"
            Write-Ok "setup.ps1 completed."
            Write-Log "setup.ps1 completed successfully" -Level "INFO"
        } else {
            Write-Fail "setup.ps1 not found at $SetupScript - run it manually."
            Write-Log "setup.ps1 not found at $SetupScript" -Level "ERROR"
        }
    }
    
    Write-Header "Bootstrap Complete"
    Write-Host "Configs: $ConfigPath" -ForegroundColor Cyan
    Write-Host "SSH Key: $env:GIT_SSH_COMMAND" -ForegroundColor Cyan
    
    # === Echo the command to run on target machine ===
    $devIp = Get-DevMachineIP
    $runCommand = "powershell -ExecutionPolicy Bypass -Command `"iwr -useb http://$devIp:8080/winbootstrap.ps1 | iex`""
    
    Write-Host ""
    Write-Host "=== To run this bootstrap on another machine ===" -ForegroundColor Cyan
    Write-Host "On the target machine, run:" -ForegroundColor Yellow
    Write-Host "  $runCommand" -ForegroundColor White
    Write-Host ""
    Write-Host "Make sure the dev machine's HTTP server is running on port 8080." -ForegroundColor Gray
    
    Write-Pause
}

# === Entry Point ===
# Handle -TestMode flag
if ($TestMode) {
    Write-Header "TestMode: Testing network connectivity"
    Write-Info "This will clone a public test repo instead of configs"
    Invoke-Bootstrap
    exit 0
}

# Handle -FindStuff flag
if ($FindStuff) {
    $result = Test-FindStuff
    Write-Pause
    exit $result
}

# Handle -CheckSsh flag
if ($CheckSsh) {
    Write-Warn "-CheckSsh flag deprecated. Use -FindStuff instead."
    $result = Test-FindStuff
    Write-Pause
    exit $result
}

# Run main bootstrap
Invoke-Bootstrap
