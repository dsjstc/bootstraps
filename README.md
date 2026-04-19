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

### bootstrap-server.ps1

Single script to install, start, stop, and uninstall the Bootstrap HTTP Server Windows Service using NSSM. Handles NSSM installation automatically.

#### Usage

**Install and start the service (automatic UAC escalation):**
```powershell
cd C:\Users\at\configs\bootstraps
.\bootstrap-server.ps1
```

**Install without starting:**
```powershell
.\bootstrap-server.ps1 -NoStart
```

**Start the service:**
```powershell
.\bootstrap-server.ps1 -Action start
```

**Stop the service:**
```powershell
.\bootstrap-server.ps1 -Action stop
```

**Uninstall the service:**
```powershell
.\bootstrap-server.ps1 -Action uninstall
```

**Use custom port:**
```powershell
.\bootstrap-server.ps1 -Port 9000
```

#### Features

- **Automatic NSSM installation** - Downloads and installs NSSM if not present
- **Automatic UAC escalation** - Just run from normal PowerShell, script requests elevation
- **Single command** - Install, start, stop, or uninstall with one script
- **Auto-display target command** - Shows the command to run on target machines

## Recommended Workflow: Dev Box → Target Machine

### bootstrap-server.ps1 (Recommended - Single Script)

1. **On dev box (vunk.x at 192.168.3.200) - One-time setup:**
    ```powershell
    cd C:\Users\at\configs\bootstraps
    .\bootstrap-server.ps1
    ```

    **What happens:**
    - Downloads and installs NSSM to `C:\Windows\System32\nssm.exe`
    - Adds URL ACL for port 8080
    - Installs Windows Service
    - Starts the service
    - Displays the command to run on target machines

2. **On target machine:**
    ```powershell
    # Paste the command displayed by bootstrap-server.ps1
    powershell -ExecutionPolicy Bypass -Command "iwr -useb http://192.168.3.200:8080/winbootstrap.ps1 | iex"
    ```

3. **When done:**
    ```powershell
    # Stop the service
    .\bootstrap-server.ps1 -Action stop
    
    # Or uninstall completely
    .\bootstrap-server.ps1 -Action uninstall
    ```

## Updating

1. Edit `bootstraps/winbootstrap.ps1`
2. Commit and push to `dsjstc/configs`
3. GitHub Actions syncs to `dsjstc/bootstraps` (~1 min)

## Dependencies

- `winget` (Windows Package Manager)
- `git` (installed by bootstrap if missing)
- `Bitwarden` (installed by bootstrap if missing)
