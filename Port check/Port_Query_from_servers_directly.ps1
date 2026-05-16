# ============================================================
# Port 135 Connectivity Test via PowerShell Remoting
# Remotes into each source server and tests TCP 135 from there
# Requires: WinRM enabled + TrustedHosts configured + admin credentials
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetServer,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 135,

    [Parameter(Mandatory=$true)]
    [string]$ServerListPath,

    [Parameter(Mandatory=$false)]
    [ValidateRange(100, 30000)]
    [int]$TimeoutMs = 2000,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\Port_Connectivity_Results.csv",

    [Parameter(Mandatory=$false)]
    [switch]$SkipCredentialCheck,

    # NOTE: Cannot use -Verbose as it is a reserved PowerShell common parameter
    [Parameter(Mandatory=$false)]
    [switch]$ShowDetail
)

# --- Validate input ---
if ([string]::IsNullOrWhiteSpace($TargetServer)) {
    Write-Error "TargetServer cannot be empty."
    exit 1
}

try {
    $targetResolved = [System.Net.Dns]::GetHostAddresses($TargetServer) | Select-Object -First 1
    if ($ShowDetail) { Write-Host "Target resolved to: $($targetResolved.IPAddressToString)" -ForegroundColor Gray }
} catch {
    Write-Warning "Could not resolve '$TargetServer'. Will attempt to connect anyway."
}

# --- Prompt for credentials ONCE ---
Write-Host "`nEnter admin credentials for the source servers..." -ForegroundColor Cyan
$Cred = Get-Credential

if ($null -eq $Cred) {
    Write-Error "Credentials are required to proceed."
    exit 1
}

# --- Load server list ---
if (-not (Test-Path $ServerListPath)) {
    Write-Error "Server list file not found: $ServerListPath"
    exit 1
}

$Extension = [System.IO.Path]::GetExtension($ServerListPath).ToLower()

if ($Extension -eq ".csv") {
    $CsvData = Import-Csv -Path $ServerListPath
    $ColName = ($CsvData | Get-Member -MemberType NoteProperty).Name |
        Where-Object { $_ -match '^(hostname|server|name|computername|ip|address)$' } |
        Select-Object -First 1
    if (-not $ColName) {
        $ColName = ($CsvData | Get-Member -MemberType NoteProperty).Name | Select-Object -First 1
    }
    Write-Host "Using CSV column: $ColName"
    $SourceServers = $CsvData.$ColName | Where-Object { $_.Trim() -ne '' }
} else {
    $SourceServers = Get-Content -Path $ServerListPath | Where-Object { $_.Trim() -ne '' }
}

if ($SourceServers.Count -eq 0) {
    Write-Error "No servers found in the file. Check the path or column name."
    exit 1
}

# --- Remove duplicates ---
$OriginalCount = $SourceServers.Count
$SourceServers = $SourceServers | Select-Object -Unique
if ($SourceServers.Count -lt $OriginalCount) {
    Write-Host "Removed $($OriginalCount - $SourceServers.Count) duplicate(s)." -ForegroundColor Gray
}

# Ensure always treated as array
if ($SourceServers -is [string]) { $SourceServers = @($SourceServers) }

Write-Host "`nLoaded $($SourceServers.Count) server(s) from file."
Write-Host "Target : $TargetServer : $Port"
Write-Host "Timeout: ${TimeoutMs}ms`n"

# --- Pre-flight credential check on first server ---
if (-not $SkipCredentialCheck) {
    Write-Host "Testing credentials on $($SourceServers[0])..." -ForegroundColor Cyan
    try {
        Invoke-Command -ComputerName $SourceServers[0] -Credential $Cred `
                       -ScriptBlock { "OK" } -ErrorAction Stop | Out-Null
        Write-Host "Credential check passed.`n" -ForegroundColor Green
    } catch {
        Write-Error "Credential check failed on $($SourceServers[0]): $_"
        Write-Host "Tip: Use -SkipCredentialCheck to bypass this check." -ForegroundColor Yellow
        exit 1
    }
}

# --- Run TCP 135 test remotely on each server ---
Write-Host "Running port $Port test on $($SourceServers.Count) server(s)..." -ForegroundColor Cyan
Write-Host ""

$Results  = @()
$ErrorLog = @()
$i        = 0

foreach ($server in $SourceServers) {
    $i++
    Write-Progress -Activity "Testing Port $Port Connectivity" `
                   -Status "[$i/$($SourceServers.Count)] $server" `
                   -PercentComplete (($i / $SourceServers.Count) * 100)

    if ($ShowDetail) { Write-Host "  -> Testing $server..." -ForegroundColor Gray }

    $remoteError  = @()
    $invokeResult = Invoke-Command -ComputerName $server `
                                   -Credential $Cred `
                                   -ErrorAction SilentlyContinue `
                                   -ErrorVariable remoteError `
                                   -ScriptBlock {
        param($Target, $Port, $TimeoutMs)

        $tc = New-Object System.Net.Sockets.TcpClient
        try {
            $connect = $tc.BeginConnect($Target, $Port, $null, $null)
            $wait    = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($wait -and -not $tc.Client.Connected) { $wait = $false }
            $tc.Close()
            $status = if ($wait) { "SUCCESS" } else { "FAILED" }
        } catch {
            $status = "FAILED"
        }

        [PSCustomObject]@{
            SourceServer = $env:COMPUTERNAME
            SourceIP     = (
                [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                Select-Object -First 1
            ).IPAddressToString
            TargetServer = $Target
            Port         = $Port
            Status       = $status
            Timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            ErrorDetails = $null
        }
    } -ArgumentList $TargetServer, $Port, $TimeoutMs

    if ($invokeResult) {
        $Results += $invokeResult
    }

    if ($remoteError.Count -gt 0) {
        foreach ($err in $remoteError) {
            $ErrorLog += "[ERROR] $server : $($err.Exception.Message)"
        }
    }
}

Write-Progress -Activity "Testing Port $Port Connectivity" -Completed

# --- Catch servers PS Remoting could not reach ---
$ReachedServers      = $Results.SourceServer
$UnreachableResults  = foreach ($s in $SourceServers) {
    if ($s -notin $ReachedServers) {
        $ErrorLog += "[UNREACHABLE] $s : PowerShell remoting connection failed"
        [PSCustomObject]@{
            SourceServer = $s
            SourceIP     = $s
            TargetServer = $TargetServer
            Port         = $Port
            Status       = "REMOTING_FAILED"
            Timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            ErrorDetails = "PowerShell remoting connection failed"
        }
    }
}

$AllResults = @($Results) + @($UnreachableResults)

# --- Console output ---
Write-Host "`n--- Results ---"
$AllResults | ForEach-Object {
    $color = switch ($_.Status) {
        "SUCCESS"         { "Green"  }
        "FAILED"          { "Red"    }
        "REMOTING_FAILED" { "Yellow" }
    }
    Write-Host "$($_.SourceIP.PadRight(20)) -> $TargetServer : $Port  [$($_.Status)]" -ForegroundColor $color
}

Write-Host "`n--- Summary ---"
Write-Host "SUCCESS        : $(($AllResults | Where-Object Status -eq 'SUCCESS').Count)" -ForegroundColor Green
Write-Host "FAILED         : $(($AllResults | Where-Object Status -eq 'FAILED').Count)"  -ForegroundColor Red
Write-Host "REMOTING_FAILED: $(($AllResults | Where-Object Status -eq 'REMOTING_FAILED').Count)" -ForegroundColor Yellow

# --- Export results CSV ---
$AllResults | Select-Object SourceServer, SourceIP, TargetServer, Port, Status, Timestamp, ErrorDetails |
    Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "`nResults saved to: $OutputPath" -ForegroundColor Green

# --- Export error log if any errors ---
if ($ErrorLog.Count -gt 0) {
    $ErrorLogPath = $OutputPath -replace '\.csv$', '_ErrorLog.txt'
    $ErrorLog | Out-File -FilePath $ErrorLogPath -Encoding UTF8
    Write-Host "Error log saved to: $ErrorLogPath" -ForegroundColor Yellow
}

Write-Host ""