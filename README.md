# Bootstraps

Windows bootstrap scripts for new PC setup.

## Published Location

Scripts are published to:  
**https://github.com/dsjstc/bootstraps**

Published via GitHub Actions workflow (`.github/workflows/sync-bootstraps.yml`) that syncs `bootstraps/` from the private `dsjstc/configs` repo on push.

## Scripts

### winbootstrap.ps1

Main bootstrap script that:
1. Installs prerequisites (git, Bitwarden)
2. Clones the configs repository
3. Runs `newpc/setup.ps1`

#### Usage

**Single-paste on virgin PC (execution policy bypass):**
```powershell
iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 | iex
```

**Enable PowerShell execution policy first (requires reboot):**
```powershell
iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 | iex -EnablePolicy
```

**Check SSH agent status:**
```powershell
iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 | iex -CheckSsh
```

**Find installed tools:**
```powershell
iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 | iex -FindStuff
```

#### Running from Local Copy / Network Drive

If you have the configs repo mapped as a network drive:

```powershell
# Map drive (example)
net use Z: \\server\share\configs

# Run from local copy
Z:\bootstraps\winbootstrap.ps1

# With EnablePolicy
Z:\bootstraps\winbootstrap.ps1 -EnablePolicy

# With custom config path
Z:\bootstraps\winbootstrap.ps1 -ConfigPath "C:\Users\$env:USERNAME\windev\configs"
```

**PowerShell execution policy workaround:**
```powershell
# Run with bypass for this session only
powershell -ExecutionPolicy Bypass -File Z:\bootstraps\winbootstrap.ps1

# Or with EnablePolicy
powershell -ExecutionPolicy Bypass -File Z:\bootstraps\winbootstrap.ps1 -EnablePolicy
```

#### Window Closing Immediately

If the PowerShell window closes immediately after running `iwr | iex`, this is expected behavior. The script completes and the window closes because there's no pause at the end.

**Workaround - Use explicit file fetch:**
```powershell
iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 -OutFile "$env:TEMP\wb.ps1"
& "$env:TEMP\wb.ps1" -FindStuff
```

This approach:
1. Downloads the script to a temp file
2. Executes it explicitly with `&`
3. Keeps the window open after completion

#### Troubleshooting

**"Parameter cannot be found" error:**
- Clear PowerShell cache: `$PSDefaultParameterValues.Clear()`
- Use explicit file fetch:
  ```powershell
  iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 -OutFile "$env:TEMP\wb.ps1"
  & "$env:TEMP\wb.ps1" -EnablePolicy
  ```

**Execution policy blocked:**
```powershell
powershell -ExecutionPolicy Bypass -File .\winbootstrap.ps1
```

---

## Architectural Notes

### Changes Needed for winbootstrap.ps1

1. **Add pause at all exit points** - The script currently exits immediately without pausing, causing the window to close. Add a pause function:

```powershell
function Write-Pause {
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
```

2. **Call pause at all exit points:**
   - Line 315: After `Write-Fail "winget not found...`
   - Line 326: After `Write-Fail "Git install failed...`
   - Line 355: After `Write-Fail "Bitwarden authentication failed...`
   - Line 377: After `Write-Fail "Clone failed...`
   - Line 413: After `Write-Host "SSH Key: $env:GIT_SSH_COMMAND"` (success path)
   - Line 419: After `exit Test-FindStuff`
   - Line 425: After `exit Test-FindStuff`

3. **Simpler commandline** - The current workaround requires two commands. Consider adding a `-Pause` switch that appends a pause at the end, or modify the script to always pause before exiting.

4. **Git not found handling** - The script currently tries to install git via winget if not found. This may fail on a virgin PC without winget. Consider:
   - Adding a check for winget first
   - Providing a fallback download link for git installer
   - Documenting the winget requirement more clearly

## Updating

1. Edit `bootstraps/winbootstrap.ps1` in the `configs` repo

2. Commit and push:
   ```powershell
   git add bootstraps/
   git commit -m "Update winbootstrap"
   git push origin main
   ```

3. GitHub Actions automatically syncs to `dsjstc/bootstraps`

4. Scripts are live at the published URL within ~1 minute

## Dependencies

- `winget` (Windows Package Manager)
- `git` (installed by bootstrap if missing)
- `Bitwarden` (installed by bootstrap if missing)
