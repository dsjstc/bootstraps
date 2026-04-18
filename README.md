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
