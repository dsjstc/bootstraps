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

**Single-paste on virgin PC:**
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
