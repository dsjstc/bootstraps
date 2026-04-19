<#
.SYNOPSIS
  Bootstrap HTTP Server Manager

.DESCRIPTION
  A simple script to start, stop, and check the status of the Bootstrap HTTP Server.
  Backgrounds bootstraps/resource/serve-http.ps1 and tracks its PID in a status file.
  No UAC required - runs entirely in user space.

.PARAMETER Action
  Action to perform: start, stop, status (default: start)

.PARAMETER Port
  Port number for the HTTP server (default: 8080).
  For -stop action, uses the port from the status file unless explicitly specified.

.PARAMETER Root
  Directory to serve files from (default: current directory)

.EXAMPLE
  .\serve-bootstrap.ps1
  # Start the HTTP server in the background

.EXAMPLE
  .\serve-bootstrap.ps1 -Command Stop
  # Stop the HTTP server

.EXAMPLE
  .\serve-bootstrap.ps1 -status
  # Check if the server is running

.EXAMPLE
  .\serve-bootstrap.ps1 -Port 9000
  # Start server on custom port
#>

param(
    [ValidateSet("Start", "Stop", "Status")]
    [string]$Command = "Start",
    [int]$Port = 8080,
    [string]$Root = $PWD.Path
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path $PSScriptRoot  # bootstraps directory
$RootDir = $PWD.Path  # Root directory (current working directory)
$StatusFile = Join-Path $RootDir ".server-status.json"
$ServeScript = Join-Path $ScriptDir "resource/serve-http.ps1"

# === Helper Functions ===

function Get-LocalIP {
    $ipAddress = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "127.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress
    
    if (-not $ipAddress) {
        $ipAddress = "192.168.3.200"
    }
    return $ipAddress
}

function Get-TargetCommand {
    $ipAddress = Get-LocalIP
    return "powershell -ExecutionPolicy Bypass -Command `"iwr -useb http://${ipAddress}:${Port}/winbootstrap.ps1 | iex`""
}

function Read-StatusFile {
    if (Test-Path $StatusFile) {
        try {
            $content = Get-Content $StatusFile -Raw -ErrorAction Stop
            return $content | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }
    return $null
}

function Write-StatusFile {
    param($StatusObject)
    $json = $StatusObject | ConvertTo-Json
    Write-Host "[DEBUG] Writing status file: $StatusFile" -ForegroundColor Gray
    Write-Host "[DEBUG] Content: $json" -ForegroundColor Gray
    $json | Set-Content $StatusFile -Encoding UTF8 -ErrorAction Stop
    Write-Host "[DEBUG] Status file written" -ForegroundColor Gray
}

function Clear-StatusFile {
    if (Test-Path $StatusFile) {
        Remove-Item $StatusFile -Force
    }
}

# === Main Logic ===

Write-Host ""
Write-Host "=== Bootstrap HTTP Server ===" -ForegroundColor Cyan
Write-Host ""

if ($Command -eq "Status") {
    $status = Read-StatusFile
    
    if (-not $status) {
        Write-Host "[STATUS] Server is not running (no status file)" -ForegroundColor Yellow
        exit 0
    }
    
    $serverPid = $status.PID
    $startTime = $status.StartTime
    $localIP = Get-LocalIP
    
    try {
        $process = Get-Process -Id $serverPid -ErrorAction Stop
        if ($process.MainModule.FileName -like "*powershell*") {
            Write-Host "[STATUS] Server is running" -ForegroundColor Green
            Write-Host "[PID]    $serverPid" -ForegroundColor Gray
            Write-Host "[PORT]   $Port" -ForegroundColor Gray
            Write-Host "[START]  $startTime" -ForegroundColor Gray
            Write-Host ""
            Write-Host "=== Target Machine Command ===" -ForegroundColor Cyan
            Write-Host "On the target machine, paste this command:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  $(Get-TargetCommand)" -ForegroundColor White
            Write-Host ""
            exit 0
        }
        else {
            Write-Host "[STATUS] Server process not found (stale status file)" -ForegroundColor Yellow
            Clear-StatusFile
            exit 1
        }
    }
    catch {
        Write-Host "[STATUS] Server process not found (stale status file)" -ForegroundColor Yellow
        Clear-StatusFile
        exit 1
    }
}

elseif ($Command -eq "Stop") {
    $status = Read-StatusFile
    
    if (-not $status) {
        Write-Host "[INFO] No running server found" -ForegroundColor Gray
        exit 0
    }
    
    # Use port from status file if not explicitly provided
    if ($Port -eq 8080) {
        $Port = $status.Port
    }
    
    $serverPid = $status.PID
    
    try {
        $process = Get-Process -Id $serverPid -ErrorAction Stop
        Write-Host "[INFO] Stopping server (PID: $serverPid)..." -ForegroundColor Gray
        $process.Close()
        $process.WaitForExit()
        Write-Host "[OK] Server stopped." -ForegroundColor Green
    }
    catch {
        Write-Host "[INFO] Server process not found" -ForegroundColor Gray
    }
    finally {
        Clear-StatusFile
    }
    
    exit 0
}

elseif ($Command -eq "Start") {
    # Check if already running
    $existingStatus = Read-StatusFile
    if ($existingStatus) {
        try {
            $existingProcess = Get-Process -Id $existingStatus.PID -ErrorAction Stop
            if ($existingProcess.MainModule.FileName -like "*powershell*") {
                Write-Host "[INFO] Server already running (PID: $($existingStatus.PID))" -ForegroundColor Yellow
                Write-Host "[PORT]   $($existingStatus.Port)" -ForegroundColor Gray
                Write-Host "[START]  $($existingStatus.StartTime)" -ForegroundColor Gray
                Write-Host ""
                Write-Host "=== Target Machine Command ===" -ForegroundColor Cyan
                Write-Host "On the target machine, paste this command:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  $(Get-TargetCommand)" -ForegroundColor White
                Write-Host ""
                exit 0
            }
        }
        catch {
            # Process not running, clear stale status
            Clear-StatusFile
        }
    }
    
    # Start the server in the background
    Write-Host "[INFO] Starting HTTP server on port $Port..." -ForegroundColor Cyan
    
    $startTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ServeScript`" -Port $Port -Root `"$Root`""
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    
    if ($process.Start()) {
        $serverPid = $process.Id
        
        # Write status file
        $statusObject = [PSCustomObject]@{
            PID = $serverPid
            Port = $Port
            StartTime = $startTime
        }
        Write-StatusFile $statusObject
        
        Write-Host "[OK] Server started in background (PID: $serverPid)" -ForegroundColor Green
        Write-Host "[INFO] Waiting for server to be ready..." -ForegroundColor Gray
        
        # Wait for server to be ready (check port)
        $ready = $false
        for ($i = 0; $i -lt 20; $i++) {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $tcp.Connect("127.0.0.1", $Port)
                $tcp.Close()
                $ready = $true
                break
            }
            catch {
                Start-Sleep -Milliseconds 200
            }
        }
        
        if ($ready) {
            Write-Host ""
            Write-Host "=== Target Machine Command ===" -ForegroundColor Cyan
            Write-Host "On the target machine, paste this command:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  $(Get-TargetCommand)" -ForegroundColor White
            Write-Host ""
            Write-Host "Use .\serve-bootstrap.ps1 -Command Stop to stop the server." -ForegroundColor Gray
        }
        else {
            Write-Host "[WARN] Server may not be ready yet" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[ERROR] Failed to start server" -ForegroundColor Red
        exit 1
    }
}
