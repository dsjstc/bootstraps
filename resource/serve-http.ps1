<#
.SYNOPSIS
  Simple HTTP Server for Serving Files from Current Directory

.DESCRIPTION
  A lightweight HTTP server that serves files from the current working directory.
  Uses raw TCP sockets - no URL ACL required, runs in user space without UAC.
  Listens on localhost by default.

.PARAMETER Port
  Port number for the HTTP server (default: 8080).

.PARAMETER Bind
  Address to bind to: 'localhost' (default), '127.0.0.1', or IP address.
  For LAN access, use your machine's IP address (e.g., '192.168.1.100').

.PARAMETER Root
  Directory to serve files from (default: current directory).

.EXAMPLE
  .\serve-http.ps1
  # Starts server on port 8080, serving current directory, bound to localhost

.EXAMPLE
  .\serve-http.ps1 -Port 9000
  # Starts server on port 9000

.EXAMPLE
  .\serve-http.ps1 -Bind 192.168.1.100
  # Starts server on port 8080, bound to specific IP for LAN access
#>

param(
    [int]$Port = 8080,
    [string]$Bind = '127.0.0.1',
    [string]$Root = $PWD.Path
)

$ErrorActionPreference = "Continue"

# === Validate Root Directory ===
if (-not (Test-Path $Root -PathType Container)) {
    Write-Host "[ERROR] Root directory not found: $Root" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Serving files from: $Root" -ForegroundColor Green
Write-Host "[INFO] HTTP Server listening on ${Bind}:${Port}" -ForegroundColor Green

# === Create TCP Listener ===
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($Bind), $Port)
$listener.Start()

Write-Host "[OK] HTTP Server started successfully." -ForegroundColor Green
Write-Host "[INFO] Press Ctrl+C to stop the server." -ForegroundColor Gray
Write-Host ""

# === Helper: Get MIME type ===
function Get-MimeType {
    param([string]$FilePath)
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    switch ($extension) {
        ".ps1" { return "application/x-powershell" }
        ".txt" { return "text/plain" }
        ".html" { return "text/html" }
        ".json" { return "application/json" }
        ".md" { return "text/markdown" }
        ".yaml" { return "application/x-yaml" }
        ".yml" { return "application/x-yaml" }
        ".sh" { return "application/x-sh" }
        ".bat" { return "application/x-bat" }
        ".cmd" { return "application/x-cmd" }
        ".js" { return "application/javascript" }
        ".css" { return "text/css" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".gif" { return "image/gif" }
        ".ico" { return "image/x-icon" }
        ".svg" { return "image/svg+xml" }
        ".pdf" { return "application/pdf" }
        ".zip" { return "application/zip" }
        ".gz" { return "application/gzip" }
        ".exe" { return "application/x-msdownload" }
        ".dll" { return "application/x-msdownload" }
        default { return "application/octet-stream" }
    }
}

# === Handle Requests ===
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 10000
        
        # Read request - read in chunks until we get CRLF CRLF (end of headers)
        $requestBytes = New-Object byte[] 65536
        $totalRead = 0
        $headerComplete = $false
        
        # Read in chunks of 1024 bytes for efficiency
        while (-not $headerComplete -and $totalRead -lt 65536) {
            $bytesRead = $stream.Read($requestBytes, $totalRead, 1024)
            if ($bytesRead -eq 0) {
                # Connection closed by client
                $stream.Close()
                $client.Close()
                break
            }
            $totalRead += $bytesRead
            
            # Check for CRLF CRLF (0x0D 0x0A 0x0D 0x0A)
            if ($totalRead -ge 4) {
                $idx = $totalRead - 1
                if ($requestBytes[$idx] -eq 0x0A -and 
                    $requestBytes[$idx-1] -eq 0x0D -and
                    $requestBytes[$idx-2] -eq 0x0A -and
                    $requestBytes[$idx-3] -eq 0x0D) {
                    $headerComplete = $true
                }
            }
        }
        
        if (-not $headerComplete) {
            # Could not parse headers
            $response = "HTTP/1.1 400 Bad Request`r`nContent-Type: text/plain`r`nContent-Length: 11`r`nConnection: close`r`n`r`nBad Request"
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($response)
            $stream.Write($responseBytes, 0, $responseBytes.Length)
            $stream.Close()
            $client.Close()
            continue
        }
        
        $requestText = [System.Text.Encoding]::ASCII.GetString($requestBytes, 0, $totalRead).Trim()
        $requestLine = $requestText.Split("`r`n")[0]
        $parts = $requestLine.Split(' ')
        
        if ($parts.Length -lt 2) {
            $response = "HTTP/1.1 400 Bad Request`r`nContent-Type: text/plain`r`nContent-Length: 11`r`nConnection: close`r`n`r`nBad Request"
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($response)
            $stream.Write($responseBytes, 0, $responseBytes.Length)
            $stream.Close()
            $client.Close()
            continue
        }
        
        $method = $parts[0]
        $url = $parts[1]
        
        Write-Host "[INFO] Request: $method $url" -ForegroundColor Gray
        
        # Map URL to file path
        $filePath = Join-Path $Root ($url -replace '^\/*', '')
        
        # Security: Ensure resolved path is within root directory
        $resolvedPath = (Get-Item $filePath).FullName
        $rootPath = (Get-Item $Root).FullName
        if (-not $resolvedPath.StartsWith($rootPath)) {
            Write-Host "[WARN] Blocked directory traversal attempt: $url" -ForegroundColor Yellow
            $response = "HTTP/1.1 403 Forbidden`r`nContent-Type: text/plain`r`nContent-Length: 9`r`nConnection: close`r`n`r`nForbidden"
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($response)
            $stream.Write($responseBytes, 0, $responseBytes.Length)
            $stream.Close()
            $client.Close()
            continue
        }
        
        if (Test-Path $filePath -PathType Leaf) {
            $content = Get-Content $filePath -Raw -Encoding UTF8
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $contentType = Get-MimeType $filePath
            
            $response = "HTTP/1.1 200 OK`r`n"
            $response += "Content-Type: $contentType`r`n"
            $response += "Content-Length: $($bodyBytes.Length)`r`n"
            $response += "Connection: close`r`n"
            $response += "`r`n"
            
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($response)
            $stream.Write($responseBytes, 0, $responseBytes.Length)
            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
        } else {
            $body = "File not found: $url"
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            
            $response = "HTTP/1.1 404 Not Found`r`n"
            $response += "Content-Type: text/plain`r`n"
            $response += "Content-Length: $($bodyBytes.Length)`r`n"
            $response += "Connection: close`r`n"
            $response += "`r`n"
            
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($response)
            $stream.Write($responseBytes, 0, $responseBytes.Length)
            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
        }
        
        $stream.Close()
        $client.Close()
    }
}
catch {
    if ($_.Exception.Message -notmatch "Operation canceled") {
        Write-Host "[ERROR] HTTP Server error: $_" -ForegroundColor Red
    }
}
finally {
    if ($listener) {
        $listener.Stop()
    }
    Write-Host "[INFO] HTTP Server stopped." -ForegroundColor Gray
}
