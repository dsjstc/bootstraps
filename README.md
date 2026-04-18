# Bootstraps

Windows bootstrap scripts for new PC setup.

## Published Location

Scripts are published to: **https://github.com/dsjstc/bootstraps**

Published via GitHub Actions workflow (`.github/workflows/sync-bootstraps.yml`) that syncs `bootstraps/` from the private `dsjstc/configs` repo on push.

## Scripts

### winbootstrap.ps1

Main bootstrap script that installs prerequisites (git, Bitwarden), clones the configs repository, and runs `newpc/setup.ps1`.

#### Usage

**Single-paste on virgin PC (bypasses execution policy):**
```powershell
powershell -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 | iex"
```

**Local run (one line):**
```powershell
powershell -ExecutionPolicy Bypass -File .\winbootstrap.ps1
```

#### Options

- `-EnablePolicy` – Enable execution policy (requires reboot)
- `-CheckSsh` – Check SSH agent status
- `-FindStuff` – Find installed tools
- `-TestMode` – Test network connectivity

#### Troubleshooting

**Window closes immediately:** Use explicit file fetch:
```powershell
powershell -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/dsjstc/bootstraps/refs/heads/main/winbootstrap.ps1 -OutFile `"$env:TEMP\wb.ps1`"; & `"$env:TEMP\wb.ps1`""
```

## Updating

1. Edit `bootstraps/winbootstrap.ps1`
2. Commit and push to `dsjstc/configs`
3. GitHub Actions syncs to `dsjstc/bootstraps` (~1 min)

## Dependencies

- `winget` (Windows Package Manager)
- `git` (installed by bootstrap if missing)
- `Bitwarden` (installed by bootstrap if missing)
