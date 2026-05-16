function Upload-ZipFile {
<#
.SYNOPSIS
    Demonstrates uploading a ZIP file to the CLAWS API.

.DESCRIPTION
    This script shows how to upload a ZIP file containing an SQLite database
    to the CLAWS API using PowerShell. It handles authentication,
    multipart form-data encoding, and provides progress feedback.

.PARAMETER ServerUrl
    The base URL of the CLAWS server (e.g., https://server.domain.com)

.PARAMETER ApiKey
    The API key for authentication. Generate this from Admin > API Keys in the web UI.

.PARAMETER ZipFilePath
    Path to the ZIP file to upload.

.PARAMETER AutoProcessingOverride
    Optional. Override the auto-processing behavior for this upload.
    Valid values:
    - ValidateOnly: Automatically validate but do not merge to production
    - ValidateAndMerge: Automatically validate and merge to production
    - Manual: Do not auto-process; require manual validation/merge
    If not specified, uses the server's global settings.

.PARAMETER TimeoutSeconds
    Request timeout in seconds. Default is 3600 (1 hour) for large files.

.EXAMPLE
    .\Upload-ZipFile.ps1 -ServerUrl "https://claws.contoso.com" `
                         -ApiKey "abc123..." `
                         -ZipFilePath "C:\Exports\permissions.zip"

.EXAMPLE
    # Upload with auto-validation only (no auto-merge)
    .\Upload-ZipFile.ps1 -ServerUrl "https://claws.contoso.com" `
                         -ApiKey "abc123..." `
                         -ZipFilePath "C:\Exports\permissions.zip" `
                         -AutoProcessingOverride "ValidateOnly"

.EXAMPLE
    # Using splatting for cleaner syntax
    $params = @{
        ServerUrl               = "https://claws.contoso.com"
        ApiKey                  = "abc123..."
        ZipFilePath             = "C:\Exports\permissions.zip"
        AutoProcessingOverride  = "ValidateAndMerge"
    }
    .\Upload-ZipFile.ps1 @params

.NOTES
    Author: CLAWS Team
    Requires: PowerShell 5.1 or later
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiKey,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ZipFilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ValidateOnly", "ValidateAndMerge", "Manual")]
    [string]$AutoProcessingOverride,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 3600
)

# Ensure TLS 1.2 is used
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Remove trailing slash from server URL if present
$ServerUrl = $ServerUrl.TrimEnd('/')

# Build the upload endpoint URL
$uploadUrl = "$ServerUrl/api/v1/upload"

Write-Host "CLAWS API Upload Script" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Validate the file exists and is a ZIP
$fileInfo = Get-Item -Path $ZipFilePath
if ($fileInfo.Extension -ne '.zip') {
    Write-Error "File must be a ZIP file. Got: $($fileInfo.Extension)"
    exit 1
}

Write-Host "File: $($fileInfo.FullName)" -ForegroundColor White
Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor White
Write-Host "Target: $uploadUrl" -ForegroundColor White
Write-Host ""

# First, check server health
Write-Host "Checking server health..." -ForegroundColor Yellow
try {
    $healthUrl = "$ServerUrl/api/v1/health"
    $healthResponse = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 30
    if ($healthResponse.success) {
        Write-Host "Server is healthy (version: $($healthResponse.data.version))" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not verify server health: $($_.Exception.Message)"
    Write-Host "Proceeding with upload anyway..." -ForegroundColor Yellow
}
Write-Host ""

# Create multipart form data
Write-Host "Preparing upload..." -ForegroundColor Yellow

try {
    # Read file bytes - use FullName to ensure absolute path for .NET methods
    $fileBytes = [System.IO.File]::ReadAllBytes($fileInfo.FullName)
    $fileName = $fileInfo.Name

    # Create boundary for multipart content
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"

    # Build multipart body - form fields MUST come BEFORE the file
    # because the server reads form fields in order and stops after processing the file
    $formFieldsBytes = @()

    # Add autoProcessingOverride form field if specified
    if ($AutoProcessingOverride) {
        Write-Host "Auto-Processing Override: $AutoProcessingOverride" -ForegroundColor White
        $overrideLines = @(
            "--$boundary",
            "Content-Disposition: form-data; name=`"autoProcessingOverride`"",
            "",
            $AutoProcessingOverride
        )
        $formFieldsBytes = [System.Text.Encoding]::UTF8.GetBytes(($overrideLines -join $LF) + $LF)
    }

    # Build file part header
    $fileHeaderLines = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
        "Content-Type: application/zip",
        ""
    )
    $fileHeaderBytes = [System.Text.Encoding]::UTF8.GetBytes(($fileHeaderLines -join $LF) + $LF)

    # Create footer
    $footerBytes = [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF")

    # Combine all parts: form fields + file header + file content + footer
    $totalLength = $formFieldsBytes.Length + $fileHeaderBytes.Length + $fileBytes.Length + $footerBytes.Length
    $bodyBytes = New-Object byte[] $totalLength
    $offset = 0

    if ($formFieldsBytes.Length -gt 0) {
        [System.Buffer]::BlockCopy($formFieldsBytes, 0, $bodyBytes, $offset, $formFieldsBytes.Length)
        $offset += $formFieldsBytes.Length
    }
    [System.Buffer]::BlockCopy($fileHeaderBytes, 0, $bodyBytes, $offset, $fileHeaderBytes.Length)
    $offset += $fileHeaderBytes.Length
    [System.Buffer]::BlockCopy($fileBytes, 0, $bodyBytes, $offset, $fileBytes.Length)
    $offset += $fileBytes.Length
    [System.Buffer]::BlockCopy($footerBytes, 0, $bodyBytes, $offset, $footerBytes.Length)

    Write-Host "Starting upload..." -ForegroundColor Yellow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Make the request using HttpWebRequest for better control in PowerShell 5.1
    $webRequest = [System.Net.HttpWebRequest]::Create($uploadUrl)
    $webRequest.Method = "POST"
    $webRequest.ContentType = "multipart/form-data; boundary=$boundary"
    $webRequest.Headers.Add("X-API-Key", $ApiKey)
    $webRequest.Accept = "application/json"
    $webRequest.Timeout = $TimeoutSeconds * 1000
    $webRequest.ContentLength = $bodyBytes.Length
    $webRequest.AllowWriteStreamBuffering = $false

    # Write the body
    $requestStream = $webRequest.GetRequestStream()
    $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $requestStream.Close()

    # Get the response
    $webResponse = $webRequest.GetResponse()
    $responseStream = $webResponse.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($responseStream)
    $responseText = $reader.ReadToEnd()
    $reader.Close()
    $webResponse.Close()

    $response = $responseText | ConvertFrom-Json

    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed

    Write-Host ""
    if ($response.success) {
        Write-Host "Upload successful!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Upload ID:      $($response.data.uploadId)" -ForegroundColor Cyan
        Write-Host "Status:         $($response.data.status)" -ForegroundColor White
        Write-Host "Message:        $($response.data.message)" -ForegroundColor White
        Write-Host "Queue Position: $($response.data.queuePosition)" -ForegroundColor White
        Write-Host ""
        Write-Host "Time elapsed: $($elapsed.ToString('mm\:ss\.fff'))" -ForegroundColor Gray

        # Calculate transfer speed
        $speedMBps = [math]::Round(($fileInfo.Length / 1MB) / $elapsed.TotalSeconds, 2)
        Write-Host "Transfer speed: $speedMBps MB/s" -ForegroundColor Gray
        Write-Host ""

        # Provide status check command
        Write-Host "To check status, run:" -ForegroundColor Yellow
        Write-Host "  Invoke-RestMethod -Uri '$ServerUrl/api/v1/upload/$($response.data.uploadId)/status' ``" -ForegroundColor White
        Write-Host "                    -Headers @{'X-API-Key'='$($ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length)))...'}" -ForegroundColor White

        # Return the upload ID for scripting
        return $response.data.uploadId
    } else {
        Write-Error "Upload failed: $($response.error.message)"
        if ($response.error.details) {
            Write-Host "Details: $($response.error.details | ConvertTo-Json -Compress)" -ForegroundColor Red
        }
        exit 1
    }

} catch [System.Net.WebException] {
    Write-Host ""
    $webException = $_.Exception
    $statusCode = $null

    if ($webException.Response) {
        $statusCode = [int]$webException.Response.StatusCode
        $responseStream = $webException.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $errorBody = $reader.ReadToEnd()
        $reader.Close()

        Write-Error "Upload failed with HTTP $statusCode"

        try {
            $errorResponse = $errorBody | ConvertFrom-Json
            if ($errorResponse.error) {
                Write-Host "Error Code: $($errorResponse.error.code)" -ForegroundColor Red
                Write-Host "Error Message: $($errorResponse.error.message)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Raw error: $errorBody" -ForegroundColor Red
        }
    } else {
        Write-Error "Upload failed: $($webException.Message)"
    }

    exit 1
} catch {
    Write-Host ""
    Write-Error "Upload failed with error: $($_.Exception.Message)"
    exit 1
}
}
