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
    [string]$OutputPath = "E:\Manoj\rds\Port135_Results.csv",

    [Parameter(Mandatory=$false)]
    [string]$CsvColumn = "",

    [Parameter(Mandatory=$false)]
    [switch]$SkipCredentialCheck
)

# -------------------------------------------------------
# STEP 1 — Load server list
# -------------------------------------------------------
if (-not (Test-Path $ServerListPath)) {
    Write-Error "Server list file not found: $ServerListPath"
    exit 1
}

$Extension     = [System.IO.Path]::GetExtension($ServerListPath).ToLower()
$SourceServers = @()

if ($Extension -eq ".csv") {
    $CsvData = Import-Csv -Path $ServerListPath

    # Determine which column to use
    $AllColumns = ($CsvData | Get-Member -MemberType NoteProperty).Name

    if ($CsvColumn -ne "" -and $AllColumns -contains $CsvColumn) {
        $ColName = $CsvColumn
    } else {
        # Auto-detect: prefer FQDN-looking values first
        $ColName = $null
        foreach ($col in $AllColumns) {
            $sample = $CsvData | Select-Object -First 10 | ForEach-Object { $_.$col }
            $fqdnCount = ($sample | Where-Object { $_ -match '\.' -and $_ -match '[a-zA-Z]' }).Count
            if ($fqdnCount -ge 1) {
                $ColName = $col
                break
            }
        }
        # Fallback: use first column
        if (-not $ColName) {
            $ColName = $AllColumns | Select-Object -First 1
        }
    }

    Write-Host "Using CSV column : '$ColName'" -ForegroundColor Cyan
    $SourceServers = $CsvData | ForEach-Object { $_.$ColName.Trim() } | Where-Object { $_ -ne '' }

} else {
    # Plain TXT — one server per line
    $SourceServers = Get-Content -Path $ServerListPath |
                     ForEach-Object { $_.Trim() } |
                     Where-Object { $_ -ne '' }
}

# -------------------------------------------------------
# STEP 2 — Deduplicate (case-insensitive)
# -------------------------------------------------------
$SourceServers = $SourceServers | Sort-Object -Unique
if ($SourceServers -is [string]) { $SourceServers = @($SourceServers) }

Write-Host "Servers loaded    : $($SourceServers.Count)" -ForegroundColor Cyan
Write-Host "Target            : $TargetServer : $Port"
Write-Host "Timeout           : ${TimeoutMs}ms`n"

# -------------------------------------------------------
# STEP 3 — Credentials
# -------------------------------------------------------
Write-Host "Enter admin credentials for the source servers..." -ForegroundColor Cyan
$Cred = Get-Credential
if ($null -eq $Cred) {
    Write-Error "Credentials are required."
    exit 1
}

# -------------------------------------------------------
# STEP 4 — Optional credential pre-flight check
# -------------------------------------------------------
if (-not $SkipCredentialCheck) {
    Write-Host "`nTesting credentials on $($SourceServers[0])..." -ForegroundColor Cyan
    try {
        Invoke-Command -ComputerName $SourceServers[0] -Credential $Cred `
                       -ScriptBlock { "OK" } -ErrorAction Stop | Out-Null
        Write-Host "Credential check passed.`n" -ForegroundColor Green
    } catch {
        Write-Error "Credential check failed on $($SourceServers[0]): $_"
        Write-Host "Tip: Use -SkipCredentialCheck to bypass." -ForegroundColor Yellow
        exit 1
    }
}

# -------------------------------------------------------
# STEP 5 — Run TCP test ONE SERVER AT A TIME
#           This avoids Invoke-Command returning both a
#           short-name result AND an FQDN/remoting-failed
#           result for the same machine (the duplication bug)
# -------------------------------------------------------
Write-Host "Testing port $Port on $($SourceServers.Count) server(s)...`n" -ForegroundColor Cyan

$AllResults = @()
$i = 0

foreach ($server in $SourceServers) {
    $i++
    Write-Progress -Activity "Port $Port Connectivity Test" `
                   -Status "[$i / $($SourceServers.Count)] $server" `
                   -PercentComplete (($i / $SourceServers.Count) * 100)

    $remoteError  = $null
    $invokeResult = $null

    try {
        $invokeResult = Invoke-Command -ComputerName $server `
                                       -Credential $Cred `
                                       -ErrorAction Stop `
                                       -ScriptBlock {
            param($Target, $Port, $TimeoutMs, $OriginalEntry)

            $sourceIP = (
                [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                Select-Object -First 1
            ).IPAddressToString

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
                SourceEntry  = $OriginalEntry        # exactly as provided in your list
                SourceServer = $env:COMPUTERNAME     # actual hostname from the machine
                SourceIP     = $sourceIP
                TargetServer = $Target
                Port         = $Port
                Status       = $status
                ErrorDetails = $null
                Timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        } -ArgumentList $TargetServer, $Port, $TimeoutMs, $server

    } catch {
        # PS Remoting could not connect
        $invokeResult = [PSCustomObject]@{
            SourceEntry  = $server
            SourceServer = $server
            SourceIP     = $server
            TargetServer = $TargetServer
            Port         = $Port
            Status       = "REMOTING_FAILED"
            ErrorDetails = $_.Exception.Message
            Timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
    }

    # Always exactly ONE result per server — no duplicates possible
    $AllResults += $invokeResult

    # Live console line per server
    $color = switch ($invokeResult.Status) {
        "SUCCESS"         { "Green"  }
        "FAILED"          { "Red"    }
        "REMOTING_FAILED" { "Yellow" }
    }
    Write-Host "$($invokeResult.SourceEntry.PadRight(55)) -> $TargetServer : $Port  [$($invokeResult.Status)]" -ForegroundColor $color
}

Write-Progress -Activity "Port $Port Connectivity Test" -Completed

# -------------------------------------------------------
# STEP 6 — Summary
# -------------------------------------------------------
Write-Host "`n--- Summary ---"
Write-Host "Total tested   : $($AllResults.Count)"
Write-Host "SUCCESS        : $(($AllResults | Where-Object Status -eq 'SUCCESS').Count)"        -ForegroundColor Green
Write-Host "FAILED         : $(($AllResults | Where-Object Status -eq 'FAILED').Count)"         -ForegroundColor Red
Write-Host "REMOTING_FAILED: $(($AllResults | Where-Object Status -eq 'REMOTING_FAILED').Count)" -ForegroundColor Yellow

# -------------------------------------------------------
# STEP 7 — Export CSV (clean columns, no PS internal cols)
# -------------------------------------------------------
$AllResults |
    Select-Object SourceEntry, SourceServer, SourceIP, TargetServer, Port, Status, ErrorDetails, Timestamp |
    Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host "`nResults saved to: $OutputPath" -ForegroundColor Green

# Export separate list of FAILED servers for easy follow-up
$FailedPath = $OutputPath -replace '\.csv$', '_FAILED_Only.csv'
$AllResults | Where-Object { $_.Status -ne 'SUCCESS' } |
    Select-Object SourceEntry, SourceServer, SourceIP, TargetServer, Port, Status, ErrorDetails, Timestamp |
    Export-Csv -Path $FailedPath -NoTypeInformation

Write-Host "Failed-only list: $FailedPath`n" -ForegroundColor Yellow