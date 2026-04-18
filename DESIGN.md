# Bootstrap Script Design Requirements

## Overview
`winbootstrap.ps1` is a Windows configuration bootstrap script that performs an interactive, idempotent setup of development tools and configuration management.

## Core Principles

### 1. Idempotence
- Running the script multiple times should produce the same result
- Already-installed components should be detected and skipped
- No destructive operations without explicit confirmation

### 2. Interactive by Default
- Default execution (`.\winbootstrap.ps1`) triggers full interactive setup
- Non-interactive flags available for automation:
  - `-FindStuff` - Run diagnostic checks only
  - `-CheckSsh` - Verify SSH agent status
  - `-SkipSetup` - Skip running setup.ps1 after bootstrap
  - `-EnablePolicy` - Enable PowerShell execution policy (requires admin)

### 3. Test Mode
- Bootstrap calls `newpc\setup.ps1 -Opt0` to test setup without elevation
- Option 0 exits immediately without attempting privilege escalation
- Allows testing bootstrap workflow in dev environments with uncommitted changes

### 4. Comprehensive Logging
- All operations logged to timestamped log file in `%TEMP%`
- Console output color-coded by severity (INFO, WARN, ERROR)
- Log file path displayed for sharing with support

### 5. Privilege Escalation Handling
- Admin-required operations explicitly checked before execution
- Clear error messages when elevation is needed

## Installation Flow

### Prerequisites Check
1. Verify `winget` is available
2. Install Git if missing
3. Install Bitwarden CLI (`bw`) if missing
4. Install Bitwarden desktop GUI if missing

### SSH Key Setup (No CLI SSH Agent)
1. Authenticate with Bitwarden (GUI or CLI)
2. Search vault for SSH key items (type 5) with "github" in notes
3. Extract private key to `~/.ssh/id_github`
4. Set `GIT_SSH_COMMAND` environment variable:
   ```powershell
   $env:GIT_SSH_COMMAND = "ssh -i C:\Users\$env:USERNAME\.ssh\id_github"
   ```
5. Clone/push to GitHub using the extracted key

### Configuration Repository
1. Clone or update `git@github.com:dsjstc/configs.git` to `~\configs`
2. Detect and reject if local changes exist (prevents data loss)
3. Run `newpc\setup.ps1` if present

## Diagnostic Functions

### Test-FindStuff
Checks for:
- Git installation
- Bitwarden desktop installation
- Configs directory existence (`~\configs`)

### Test-CheckSsh
Checks for:
- Bitwarden desktop process running
- SSH socket existence
- ssh-add communication with agent

## Error Handling

- All winget operations logged with full output
- PATH refresh after installs with verification
- Timeout handling for socket creation and key loading
- Clear exit codes for automation integration

## File Locations

| Component | Location |
|-----------|----------|
| Script | `bootstraps\winbootstrap.ps1` |
| Log file | `%TEMP%\winbootstrap-YYYYMMDD-HHMMSS\winbootstrap.log` |
| Configs repo | `~\configs` |
| SSH key file | `~\.ssh\id_github` |
| Bitwarden CLI | `%LOCALAPPDATA%\Programs\Bitwarden\bw.exe` |
| Bitwarden GUI | `%LOCALAPPDATA%\Programs\Bitwarden\Bitwarden.exe` |

---

# Recent Changes to winbootstrap.ps1

## Change Log

### 1. isRunningDirectly Detection (Line 22)
**Problem:** Script did nothing when run directly.
**Cause:** `$MyInvocation.ScriptName -eq $MyInvocation.MyCommand.Path` was returning false.
**Fix:** Changed to:
```powershell
$script:isRunningDirectly = [string]::IsNullOrEmpty($MyInvocation.ScriptName)
```

### 2. Configs Directory Path (Line ~50)
**Problem:** Hardcoded wrong path `C:\Users\$env:USERNAME\windev\configs`.
**Fix:** Changed to `C:\Users\$env:USERNAME\configs` (user confirmed `~/configs` is correct).

### 3. SSH Check - Removed winssh-pageant (Line ~150)
**Problem:** Script checked for winssh-pageant which user doesn't use.
**Fix:** Removed winssh-pageant check from Test-CheckSsh function.

### 4. winget Install ID (Line ~200)
**Problem:** Using `Bitwarden.bw` instead of correct ID.
**Fix:** Changed to `Bitwarden.CLI`.

### 5. bw CLI Executable Detection (Line ~267)
**Problem:** bw CLI installed but not in PATH, registry InstallLocation was empty.
**Fix:** Added registry-based executable path search plus WinGet packages directory search in Start-BwSshAgent function.

### 6. Duplicate Function Definitions
**Problem:** Write-Header, Write-Step, Write-Ok, Write-Fail, Write-Info defined twice.
**Fix:** Removed second set of definitions.

### 7. SSH Agent Support Detection (Line ~267-352)
**Problem:** bw CLI version 2026.3.0 doesn't have ssh-agent command (added in v2025.7.0+).
**Fix:** Added detection for ssh-agent support, script continues gracefully without failing:
```powershell
$bwHelp = bw help 2>&1
if ($bwHelp -notmatch 'ssh-agent') {
    Write-Warn "Bitwarden CLI does not support ssh-agent command (requires v2025.7.0+)"
    Write-Info "SSH agent functionality requires Bitwarden CLI v2025.7.0 or later"
    Write-Info "The Bitwarden desktop GUI has built-in SSH agent support"
    return $true
}
```

### 8. Removed --server Option (Line ~380)
**Problem:** Newer bw CLI versions don't support --server flag.
**Fix:** Removed --server option, use default server URL.

### 9. Git Pull - Skip on Uncommitted Changes (Line ~500)
**Problem:** Script exited with error when configs repo had local changes.
**Fix:** Skip git pull when uncommitted changes exist (dev environment), continue with bootstrap.

### 10. Authentication Status Check (Line ~360)
**Problem:** Script checked for `"loggedIn":true` but bw status returns `"status":"locked"` or `"status":"unlocked"`.
**Fix:** Updated regex to check for `"status":"unlocked"`:
```powershell
$bwStatus = bw status 2>&1
if ($bwStatus -match '"status":"unlocked"') {
    Write-Ok "Already logged in to Bitwarden"
    return $true
}
```

### 11. .env File Loading (Line ~43-60)
**Problem:** .env loading ran before Write-Log function was defined.
**Fix:** Moved .env loading code to after Write-Log function definition.

### 12. BW_MASTER_PW Environment Variable (Line ~43-60)
**Problem:** Using `${env:$key}` syntax doesn't work with dynamic variable names.
**Fix:** Changed to `[Environment]::SetEnvironmentVariable($key, $value, 'Process')`:
```powershell
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
```

### 13. Start-BwAuth Function (Line ~354-443)
**Problem:** Script needed to handle locked vault state and auto-unlock.
**Fix:** Implemented vault unlock with BW_MASTER_PW from .env file:
```powershell
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
                Write-Ok "Vault unlocked successfully"
                Write-Log "Vault unlocked using BW_MASTER_PW" -Level "INFO"
                return $true
            } else {
                Write-Fail "Failed to unlock with BW_MASTER_PW"
                Write-Log "Vault unlock failed with BW_MASTER_PW" -Level "ERROR"
                return $false
            }
        }
        
        # No password available - fail without prompting
        Write-Fail "BW_MASTER_PW environment variable not set. Cannot unlock vault without prompting."
        Write-Log "Vault unlock failed: BW_MASTER_PW not set" -Level "ERROR"
        return $false
    }
    # ... rest of function
}
```

### 14. Setup Script Call (Line ~940-954)
**Problem:** setup.ps1 was attempting elevation.
**Fix:** Changed bootstrap to call setup.ps1 with `-Opt0` flag:
```powershell
# === Run setup.ps1 ===
if (-not $SkipSetup) {
    Write-Header "Running setup script"
    $SetupScript = Join-Path $ConfigPath "newpc\setup.ps1"
    if (Test-Path $SetupScript) {
        Write-Log "Running setup.ps1 with -0 option (exit immediately)" -Level "INFO"
        $setupExitCode = & $SetupScript -Opt0
        Write-Log "setup.ps1 exited with code: $setupExitCode" -Level "INFO"
        Write-Ok "setup.ps1 completed."
        Write-Log "setup.ps1 completed successfully" -Level "INFO"
    } else {
        Write-Fail "setup.ps1 not found at $SetupScript - run it manually."
        Write-Log "setup.ps1 not found at $SetupScript" -Level "ERROR"
    }
}
```

---

# Recent Changes to newpc/setup.ps1

## Change Log

### 1. Opt0 Parameter (Line ~1)
**Problem:** setup.ps1 was attempting elevation before processing parameters.
**Fix:** Added Opt0 parameter and moved param block before self-elevation check:
```powershell
param(
    [switch]$SkipInteractive,
    [switch]$DryRun,
    [switch]$Rollback,
    [string]$RollbackId,
    [switch]$TestAll,
    [int]$TestOption,
    [switch]$ShowState,
    [switch]$ShowLog,
    [switch]$All,
    [switch]$Help,
    [switch]$Opt0,
    [switch]$Opt1,
    # ... other options
)

# Option 0: Exit immediately without elevation (for testing)
if ($Opt0) {
    Write-Host "Option 0: Exiting immediately without elevation (testing mode)" -ForegroundColor Gray
    exit 0
}
```

---

# SSH Key Export Feature

## Discovery
- Bitwarden GUI cannot export SSH keys directly to `~/.ssh/`
- Bitwarden CLI can fetch SSH keys stored as type 5 (SSH Key) items
- Property name is `sshkey.privateKey` (camelCase), NOT `sshkey.private` (snake_case)

## Implementation
Script `scripts/test-bw-fetch.ps1` implements:
1. Unlock vault with BW_MASTER_PW
2. List all items and find SSH keys (type 5) with "github" in notes
3. Extract `sshkey.privateKey` property
4. Write to `~/.ssh/id_github` without BOM (UTF8 encoding)
5. Verify with `ssh -T git@github.com`

## Verification
```
ssh -T -i C:\Users\at\.ssh\id_github git@github.com
# Output: Hi dsjstc! You've successfully authenticated, but GitHub does not provide shell access.
```

## Usage Without SSH Config
```powershell
# Git command-line flag
git -c core.sshCommand="ssh -i C:\Users\at\.ssh\id_wunk" clone git@github.com:username/repo.git

# Environment variable
$env:GIT_SSH_COMMAND = "ssh -i C:\Users\at\.ssh\id_wunk"
git clone git@github.com:username/repo.git
```
