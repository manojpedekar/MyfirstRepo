# ===============================
# Configuration
# ===============================
$PortQryPath = "C:\Temp\PortQry.exe"
$ServersListPath  = "C:\Temp\Servers.txt"
$OutputFile  = "C:\Temp\PortQry_Results.txt"
$CsvOutput   = "C:\Temp\PortQry_Results.csv"
$Throttle    = 10   # Parallel limit

# ===============================
# Validation
# ===============================
if (!(Test-Path $PortQryPath)) {
    throw "ERROR: PortQry.exe not found at $PortQryPath"
}

if (!(Test-Path $ServersListPath)) {
    throw "ERROR: Servers list not found at $ServersListPath"
}

Remove-Item $OutputFile, $CsvOutput -ErrorAction SilentlyContinue

# ===============================
# Ports to test
# ===============================
$Ports = @(
    @{ Port = 53;   Protocol = "TCP" }
    @{ Port = 53;   Protocol = "UDP" }
    @{ Port = 88;   Protocol = "TCP" }
    @{ Port = 88;   Protocol = "UDP" }
    @{ Port = 123;  Protocol = "UDP" }
    @{ Port = 135;  Protocol = "TCP" }
    @{ Port = 389;  Protocol = "TCP" }
    @{ Port = 389;  Protocol = "UDP" }
    @{ Port = 445;  Protocol = "TCP" }
    @{ Port = 464;  Protocol = "TCP" }
    @{ Port = 464;  Protocol = "UDP" }
    @{ Port = 636;  Protocol = "TCP" }
    @{ Port = 3268; Protocol = "TCP" }
    @{ Port = 3269; Protocol = "TCP" }
    @{ Port = 9389; Protocol = "TCP" }
)

# ===============================
# Load Servers
# ===============================
$Servers = Get-Content $ServersListPath |
       Where-Object { $_ -and $_ -notmatch '^\s*#' } |
       ForEach-Object { $_.Trim() }

# ===============================
# Header
# ===============================
Add-Content $OutputFile "Port Check Report"
Add-Content $OutputFile "Generated on: $(Get-Date)"
Add-Content $OutputFile ""

Write-Host "Running port checks in parallel (Throttle = $Throttle)..."

# ===============================
# Parallel Execution
# ===============================
$Results = $Servers | ForEach-Object -Parallel {
    param ($Ports, $PortQryPath)

    $Servers = $_
    $TextOutput = @()
    $CsvRows = @()

    $TextOutput += "========================================"
    $TextOutput += "Testing Servers: $Servers"
    $TextOutput += "========================================"

    foreach ($Port in $Ports) {
        $PortNumber = $Port.Port
        $Protocol   = $Port.Protocol

        try {
            $Result = & $PortQryPath -n $Servers -p $Protocol -e $PortNumber 2>&1
        }
        catch {
            $Result = $null
        }

        if (-not $Result) {
            $Status = "NO RESPONSE"
        }
        elseif ($Result -match "LISTENING") {
            $Status = "LISTENING"
        }
        elseif ($Result -match "NOT LISTENING") {
            $Status = "NOT LISTENING"
        }
        elseif ($Result -match "FILTERED") {
            $Status = "FILTERED"
        }
        else {
            $Status = "UNKNOWN"
        }

        $TextOutput += "---- $Protocol $PortNumber ----"
        $TextOutput += ($Result ?? "No output returned")
        $TextOutput += ""

        $CsvRows += [PSCustomObject]@{
            Timestamp        = Get-Date
            Servers = $Servers
            Port             = $PortNumber
            Protocol         = $Protocol
            Status           = $Status
        }
    }

    [PSCustomObject]@{
        Text = $TextOutput
        Csv  = $CsvRows
    }

} -ThrottleLimit $Throttle -ArgumentList $Ports, $PortQryPath

# ===============================
# Collect Results
# ===============================
$AllCsvRows = @()

foreach ($Result in $Results) {
    Add-Content $OutputFile ($Result.Text -join "`n")
    $AllCsvRows += $Result.Csv
}

$AllCsvRows | Export-Csv $CsvOutput -NoTypeInformation -Force

# ===============================
# Summary Report
# ===============================
Write-Host "`n Port check completed"
Write-Host "Text report: $OutputFile"
Write-Host "CSV report:  $CsvOutput"

Write-Host "`nSummary of Failed Ports:"
$Failures = $AllCsvRows | Where-Object { $_.Status -ne "LISTENING" }

if ($Failures) {
    $Failures | Group-Object Servers | ForEach-Object {
        Write-Host "`n$($_.Name):"
        $_.Group | ForEach-Object {
            Write-Host "  $($_.Protocol) $($_.Port) - $($_.Status)"
        }
    }
}
else {
    Write-Host "No failures detected"
}
