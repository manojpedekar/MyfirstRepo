# ===============================
# Configuration
# ===============================
$Config = @{
    PortQryPath     = "C:\Temp\PortQry.exe"
    ServersListPath = "C:\Temp\Servers.txt"
    OutputFolder    = "C:\Temp\PortQry_Results"
    Throttle        = 5        # Max concurrent server checks
    PortTimeout     = 5        # Seconds
    Ports           = @(
        @{ Port=53; Protocol="TCP" },
        @{ Port=53; Protocol="UDP" },
        @{ Port=88; Protocol="TCP" },
        @{ Port=88; Protocol="UDP" },
        @{ Port=123; Protocol="UDP" },
        @{ Port=135; Protocol="TCP" },
        @{ Port=389; Protocol="TCP" },
        @{ Port=389; Protocol="UDP" },
        @{ Port=445; Protocol="TCP" },
        @{ Port=464; Protocol="TCP" },
        @{ Port=464; Protocol="UDP" },
        @{ Port=636; Protocol="TCP" },
        @{ Port=3268; Protocol="TCP" },
        @{ Port=3269; Protocol="TCP" },
        @{ Port=9389; Protocol="TCP" }
    )
}

# Ensure output folder exists
if (!(Test-Path $Config.OutputFolder)) { New-Item -Path $Config.OutputFolder -ItemType Directory | Out-Null }

# Validate paths
if (!(Test-Path $Config.PortQryPath)) { throw "PortQry.exe not found at $($Config.PortQryPath)" }
if (!(Test-Path $Config.ServersListPath)) { throw "Servers list not found at $($Config.ServersListPath)" }

# Remove old CSVs
Get-ChildItem $Config.OutputFolder\* -Include *.csv -ErrorAction SilentlyContinue | Remove-Item -Force

# Load servers
$Servers = Get-Content $Config.ServersListPath | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }

# ===============================
# Job Script: Test one server
# ===============================
$ServerJobScript = {
    param($Server, $Ports, $PortQryPath, $PortTimeout)

    # Define Test-Port inside the job
    function Test-Port {
        param([string]$Server,[int]$Port,[string]$Protocol,[string]$PortQryPath,[int]$Timeout)

        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessInfo.FileName = $PortQryPath
        $ProcessInfo.Arguments = "-n $Server -p $Protocol -e $Port"
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.RedirectStandardError  = $true
        $ProcessInfo.UseShellExecute = $false
        $ProcessInfo.CreateNoWindow = $true

        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo
        $Process.Start() | Out-Null

        if (-not $Process.WaitForExit($Timeout*1000)) {
            $Process.Kill()
            return [PSCustomObject]@{Server=$Server; Port=$Port; Protocol=$Protocol; Status="TIMEOUT"; Result=$null}
        }

        $Output = $Process.StandardOutput.ReadToEnd() + $Process.StandardError.ReadToEnd()
        $Status = if ($Output -match '(?i)LISTENING') {"LISTENING"}
                  elseif ($Output -match '(?i)NOT LISTENING') {"NOT LISTENING"}
                  elseif ($Output -match '(?i)FILTERED') {"FILTERED"}
                  elseif (-not $Output) {"NO RESPONSE"}
                  else {"UNKNOWN"}

        return [PSCustomObject]@{Server=$Server; Port=$Port; Protocol=$Protocol; Status=$Status; Result=$Output}
    }

    $CsvRows = @()
    foreach ($Port in $Ports) {
        $CsvRows += Test-Port -Server $Server -Port $Port.Port -Protocol $Port.Protocol -PortQryPath $PortQryPath -Timeout $PortTimeout
    }
    return $CsvRows
}

# ===============================
# Run jobs for servers with throttle
# ===============================
$Jobs = @()
foreach ($Server in $Servers) {
    while ((Get-Job -State Running).Count -ge $Config.Throttle) { Start-Sleep -Seconds 1 }
    $Jobs += Start-Job -ScriptBlock $ServerJobScript -ArgumentList $Server, $Config.Ports, $Config.PortQryPath, $Config.PortTimeout
}

# ===============================
# Collect results
# ===============================
$AllCsvRows = @()
foreach ($Job in $Jobs) {
    $Result = Receive-Job $Job -Wait
    $AllCsvRows += $Result
    Remove-Job $Job
}

# Export master CSV
$CsvOutput = Join-Path $Config.OutputFolder "PortQry_Results.csv"
$AllCsvRows | Export-Csv $CsvOutput -NoTypeInformation -Force

# Export summary CSV (failed ports per server)
$ServerSummaries = $AllCsvRows | Group-Object Server | ForEach-Object {
    $Failed = ($_.Group | Where-Object {$_.Status -ne "LISTENING"}).Count
    [PSCustomObject]@{
        Server  = $_.Name
        TotalPorts = $_.Group.Count
        Failed  = $Failed
        Result  = if ($Failed -eq 0) {"PASS"} else {"FAIL"}
    }
}
$SummaryCsv = Join-Path $Config.OutputFolder "Server_Summary.csv"
$ServerSummaries | Export-Csv $SummaryCsv -NoTypeInformation -Force

# ===============================
# Console summary
# ===============================
Write-Host "`nPort check completed."
Write-Host "Master CSV: $CsvOutput"
Write-Host "Summary CSV: $SummaryCsv"

# Show failed ports
$Failures = $AllCsvRows | Where-Object {$_.Status -ne "LISTENING"}
if ($Failures) {
    Write-Host "`nPer-server FAILED ports:"
    $Failures | Group-Object Server | ForEach-Object {
        Write-Host "`n$($_.Name):"
        $_.Group | ForEach-Object { Write-Host "  $($_.Protocol) $($_.Port) - $($_.Status)" }
    }
} else {
    Write-Host "No failures detected."
}
