<#
bootstrap.ps1 - Windows Config Bootstrap Script
#####################################################
v0.9.  Untested in the wild.

Run with:

iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 | iex
#>

param(
    [string]$ConfigPath,
    [string]$BitwardenItem = "github-ssh-key",
    [switch]$SkipSetup,
    [switch]$FindStuff,
    [switch]$CheckSsh
)

# Set default ConfigPath if not provided
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = "C:\Users\$env:USERNAME\windev\configs"
}

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
function Get-BitwardenSshSocket {
    # Bitwarden SSH agent on Windows uses a named pipe
    # The socket path is typically: \\.\pipe\bitwarden-ssh-agent
    return '\\.\pipe\bitwarden-ssh-agent'
}

function Test-SshAgentHasKey {
    # First, ensure SSH_AUTH_SOCK is set for Bitwarden's agent
    if (-not $env:SSH_AUTH_SOCK) {
        $bwSocket = Get-BitwardenSshSocket
        if (Test-Path $bwSocket) {
            $env:SSH_AUTH_SOCK = $bwSocket
        }
    }
    
    # Check if Bitwarden SSH agent process is running
    $bwSshAgent = Get-Process -Name 'winssh-pageant' -ErrorAction SilentlyContinue
    if (-not $bwSshAgent) {
        Write-Info "Bitwarden SSH agent (winssh-pageant) not running"
        return $false
    }
    
    # Try ssh-add -l to check for loaded keys
    $result = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0 -and $result -notmatch "no identities" -and $result -notmatch "Could not open a connection to your authentication agent") {
        return $true
    }
    
    # Alternative: Check if we can communicate with the agent
    try {
        $testResult = ssh-add -l 2>&1
        if ($testResult -notmatch "Could not open a connection" -and $testResult -notmatch "socket") {
            return $true
        }
    } catch {
        # If we get here, the agent might not have keys loaded
    }
    
    return $false
}

function Set-BitwardenSshAgentEnv {
    # Set SSH_AUTH_SOCK environment variable for Bitwarden SSH agent
    $socketPath = Get-BitwardenSshSocket
    
    # Set for current process
    $env:SSH_AUTH_SOCK = $socketPath
    
    # Set for system environment (requires admin, so we just set for current session)
    [System.Environment]::SetEnvironmentVariable('SSH_AUTH_SOCK', $socketPath, 'User')
    
    Write-Info "SSH_AUTH_SOCK set to: $socketPath"
}

# === CheckSSH Subroutine ===
function Test-CheckSsh {
    Write-Header "Bitwarden SSH Agent Check"
    $allPassed = $true
    
    # Check 1: Verify winssh-pageant process is running
    Write-Step 1 "winssh-pageant process"
    $bwSshAgent = Get-Process -Name 'winssh-pageant' -ErrorAction SilentlyContinue
    if ($bwSshAgent) {
        Write-Ok "winssh-pageant is running (PID: $($bwSshAgent.Id))"
    } else {
        Write-Fail "winssh-pageant process not found"
        $allPassed = $false
    }
    
    # Check 2: Verify Bitwarden desktop process is running
    Write-Step 2 "Bitwarden desktop process"
    $bwProcess = Get-Process -Name 'Bitwarden' -ErrorAction SilentlyContinue
    if ($bwProcess) {
        Write-Ok "Bitwarden desktop is running ($($bwProcess.Count) process(es))"
    } else {
        Write-Fail "Bitwarden desktop process not found"
        $allPassed = $false
    }
    
    # Check 3: Verify Bitwarden SSH socket named pipe exists
    Write-Step 3 "SSH socket named pipe"
    $socketPath = Get-BitwardenSshSocket
    try {
        # On Windows, Test-Path works with named pipes
        if (Test-Path $socketPath) {
            Write-Ok "Socket pipe exists: $socketPath"
        } else {
            Write-Fail "Socket pipe not found: $socketPath"
            $allPassed = $false
        }
    } catch {
        Write-Fail "Could not check socket pipe: $_"
        $allPassed = $false
    }
    
    # Check 4: Set SSH_AUTH_SOCK and test ssh-add communication
    Write-Step 4 "ssh-add communication"
    Set-BitwardenSshAgentEnv
    
    # Find ssh-add.exe
    $sshAddPath = $null
    $sshPaths = @(
        'C:\Windows\System32\OpenSSH\ssh-add.exe',
        'C:\Program Files\Git\usr\bin\ssh-add.exe',
        'C:\Program Files\Git\bin\ssh-add.exe'
    )
    foreach ($path in $sshPaths) {
        if (Test-Path $path) {
            $sshAddPath = $path
            break
        }
    }
    
    if (-not $sshAddPath) {
        Write-Fail "ssh-add.exe not found"
        $allPassed = $false
    } else {
        Write-Info "Using ssh-add.exe: $sshAddPath"
        $result = & $sshAddPath -l 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Ok "ssh-add -l succeeded - keys are loaded"
            Write-Info "  Output: $result"
        } elseif ($exitCode -eq 2 -and $result -match "no identities") {
            Write-Ok "ssh-add -l succeeded - no keys loaded (agent is working)"
            Write-Info "  Output: $result"
        } elseif ($result -match "Could not open a connection" -or $result -match "No such file") {
            Write-Fail "Could not connect to SSH agent: $result"
            $allPassed = $false
        } else {
            Write-Ok "ssh-add -l returned (agent responding)"
            Write-Info "  Exit code: $exitCode"
            Write-Info "  Output: $result"
        }
    }
    
    Write-Header "CheckSSH Complete"
    if ($allPassed) {
        Write-Ok "All SSH agent checks passed."
        return 0
    } else {
        Write-Fail "Some SSH agent checks failed."
        return 1
    }
}

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
    
    # Check Bitwarden
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

    $bwPath = "C:\Users\$env:USERNAME\AppData\Local\Programs\Bitwarden\Bitwarden.exe"
    if (-not (Test-Path $bwPath)) {
        Write-Info "Installing Bitwarden desktop..."
        winget install --id Bitwarden.Bitwarden -e --silent --accept-source-agreements --accept-package-agreements
        Write-Ok "Bitwarden installed."
    } else {
        Write-Ok "Bitwarden already installed."
    }

    # === Step 3: Wait for Bitwarden SSH Agent ===
    Write-Step 3 "Bitwarden SSH agent"

    # Set SSH_AUTH_SOCK environment variable for Bitwarden's SSH agent
    Set-BitwardenSshAgentEnv

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
            Write-Fail "setup.ps1 not found at $SetupScript - run it manually."
        }
    }

    Write-Header "Bootstrap Complete"
    Write-Host "Configs: $ConfigPath" -ForegroundColor Cyan
}

# === Entry Point ===
# Handle -FindStuff flag
if ($FindStuff) {
    exit Test-FindStuff
}

# Handle -CheckSsh flag
if ($CheckSsh) {
    exit Test-CheckSsh
}

# Run main bootstrap
Invoke-Bootstrap
