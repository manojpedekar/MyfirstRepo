<#
.SYNOPSIS
    Validates RPC connectivity from the local server to one or more Certificate
    Authority (CA) servers by testing TCP/135 and the dynamic RPC ports that the
    remote CA services have actually registered with the RPC Endpoint Mapper.

.DESCRIPTION
    A raw TCP sweep of the dynamic RPC range (49152-65535) is not a meaningful
    firewall test: a port in that range only accepts a connection when a service
    happens to be listening on it, and RPC services choose those ports randomly at
    startup. Even when a firewall fully permits the range, ~16,380 of the 16,384
    ports report "closed", which tells you nothing about the firewall rule.

    The authoritative validation is:
        1. Test TCP/135 (RPC Endpoint Mapper) - always listening on a CA.
        2. Query the Endpoint Mapper (via Microsoft's PortQry) to learn which
           dynamic ports the remote RPC interfaces have registered.
        3. Test connectivity to those specific dynamic ports.

    This script performs exactly that, in parallel, and writes a timestamped CSV
    and log to the output folder plus an on-screen pass/fail summary per server.

    TCP status classification:
        Open     - TCP handshake completed (port reachable and listening).
        Closed   - Connection actively refused (RST) - reachable host, no listener.
        Filtered - Connection timed out - typically a firewall silently dropping
                   packets, or the host is unreachable.

.PARAMETER ComputerName
    One or more CA server FQDNs / hostnames / IPs. Defaults to the five
    SS&C GlobeOp Issuing CA servers.

.PARAMETER EndpointMapperPort
    RPC Endpoint Mapper port. Default 135.

.PARAMETER PortQryPath
    Full path to PortQry.exe. If omitted, the script searches PATH, the script
    directory, and common install locations.

.PARAMETER TimeoutMs
    Per-port TCP connect timeout in milliseconds. Default 1500.

.PARAMETER ThrottleLimit
    Maximum concurrent TCP tests. Default 100.

.PARAMETER OutputPath
    Folder for the CSV and log. Default C:\temp.

.EXAMPLE
    .\Test-CaRpcConnectivity_v1.ps1

    Tests the five default CA servers.

.EXAMPLE
    .\Test-CaRpcConnectivity_v1.ps1 -ComputerName ca1.contoso.com -TimeoutMs 2000

.NOTES
    Author  : Manoj Pedekar
    Version : 1.0
    Requires: PowerShell 5.1+ (works on 2008 R2 with WMF 5.1). PortQry.exe is
              required only for the dynamic-port discovery phase; TCP/135 testing
              works without it.
    PortQry : Free Microsoft tool - "PortQryV2" on the Microsoft Download Center.
              Place PortQry.exe on PATH, in this script's folder, or pass -PortQryPath.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName = @(
        '10-222-84-85.globeop.com',   # SS&C GlobeOp Issuing CA1
        '10-234-43-62.globeop.com',   # SS&C GlobeOp Issuing CA2
        '10-239-31-94.globeop.com',   # SS&C GlobeOp Issuing CA3
        '10-57-57-85.globeop.com',    # SSNC GLOBEOP Issuing CA4
        '10-136-50-34.globeop.com'    # SSNC GLOBEOP Issuing CA5
    ),

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$EndpointMapperPort = 135,

    [Parameter()]
    [string]$PortQryPath,

    [Parameter()]
    [ValidateRange(100, 60000)]
    [int]$TimeoutMs = 1500,

    [Parameter()]
    [ValidateRange(1, 500)]
    [int]$ThrottleLimit = 100,

    [Parameter()]
    [string]$OutputPath = 'C:\temp'
)

#region Setup ----------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$runStamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path $OutputPath ("CaRpcConnectivity_{0}.csv" -f $runStamp)
$logPath   = Join-Path $OutputPath ("CaRpcConnectivity_{0}.log" -f $runStamp)

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "{0} [{1}] {2}" -f $ts, $Level, $Message
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line -ForegroundColor Gray }
    }
    Add-Content -LiteralPath $logPath -Value $line
}

#endregion

#region Helper functions -----------------------------------------------------

# Runspace-friendly TCP connect test. Classifies Open / Closed / Filtered.
$tcpTestScript = {
    param($Target, $TimeoutMs)

    $result = [pscustomobject]@{
        ComputerName   = $Target.ComputerName
        ResolvedIP     = $Target.ResolvedIP
        Port           = $Target.Port
        PortType       = $Target.PortType
        Status         = 'Unknown'
        ResponseTimeMs = $null
        Timestamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }

    $sw     = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Target.ResolvedIP, $Target.Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $result.Status = 'Filtered'   # timed out - firewall drop or unreachable
        }
        else {
            try {
                $client.EndConnect($iar)
                $result.Status = 'Open'
            }
            catch {
                $result.Status = 'Closed' # RST - reachable host, no listener
            }
        }
    }
    catch {
        $result.Status = 'Closed'
    }
    finally {
        $sw.Stop()
        $result.ResponseTimeMs = [int]$sw.ElapsedMilliseconds
        $client.Close()
    }
    $result
}

function Invoke-ParallelPortTest {
    param(
        [Parameter(Mandatory)][object[]]$Targets,
        [Parameter(Mandatory)][int]$TimeoutMs,
        [Parameter(Mandatory)][int]$ThrottleLimit,
        [Parameter(Mandatory)][scriptblock]$TestScript
    )

    $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()
    $handles = New-Object System.Collections.ArrayList

    foreach ($t in $Targets) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($TestScript).AddArgument($t).AddArgument($TimeoutMs)
        [void]$handles.Add([pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() })
    }

    $results = New-Object System.Collections.ArrayList
    foreach ($h in $handles) {
        try   { [void]$results.AddRange(@($h.PS.EndInvoke($h.Handle))) }
        catch { Write-Log "Runspace error: $($_.Exception.Message)" -Level 'ERROR' }
        finally { $h.PS.Dispose() }
    }

    $pool.Close()
    $pool.Dispose()
    return $results
}

function Resolve-TargetHost {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $ip = ([System.Net.Dns]::GetHostAddresses($Name) |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                Select-Object -First 1).IPAddressToString
        if (-not $ip) { $ip = ([System.Net.Dns]::GetHostAddresses($Name) | Select-Object -First 1).IPAddressToString }
        return $ip
    }
    catch {
        return $null
    }
}

function Get-PortQryExe {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath) { return (Resolve-Path -LiteralPath $ExplicitPath).Path }
        else { throw "PortQry.exe not found at supplied -PortQryPath: $ExplicitPath" }
    }

    $onPath = Get-Command -Name 'portqry.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @(
        (Join-Path $PSScriptRoot 'PortQry.exe'),
        'C:\PortQryV2\PortQry.exe',
        'C:\Program Files\Support Tools\PortQry.exe',
        (Join-Path $OutputPath 'PortQry.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

# Parses "portqry -n <host> -e 135" output and returns the unique TCP dynamic ports.
function Get-EndpointMapperPorts {
    param(
        [Parameter(Mandatory)][string]$PortQryExe,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port
    )

    $raw = & $PortQryExe -n $ComputerName -e $Port -p TCP 2>&1
    $ports = New-Object System.Collections.Generic.HashSet[int]

    foreach ($line in $raw) {
        # Matches: ncacn_ip_tcp:10.222.84.85[49664]
        if ($line -match 'ncacn_ip_tcp:[^\[]+\[(\d+)\]') {
            [void]$ports.Add([int]$Matches[1])
        }
    }
    return ,@($ports)
}

#endregion

#region Main -----------------------------------------------------------------

Write-Log "===== CA RPC connectivity check started on $env:COMPUTERNAME =====" -Level 'INFO'
Write-Log "Targets: $($ComputerName -join ', ')" -Level 'INFO'
Write-Log "Timeout: ${TimeoutMs}ms | ThrottleLimit: $ThrottleLimit | Output: $OutputPath" -Level 'INFO'

# --- Resolve hosts -----------------------------------------------------------
$hosts = foreach ($name in $ComputerName) {
    $ip = Resolve-TargetHost -Name $name
    if ($ip) { Write-Log "Resolved $name -> $ip" -Level 'INFO' }
    else     { Write-Log "DNS resolution FAILED for $name" -Level 'ERROR' }
    [pscustomobject]@{ ComputerName = $name; ResolvedIP = $ip }
}

# --- Phase 1: test TCP/135 ---------------------------------------------------
$empTargets = foreach ($h in $hosts) {
    if ($h.ResolvedIP) {
        [pscustomobject]@{
            ComputerName = $h.ComputerName
            ResolvedIP   = $h.ResolvedIP
            Port         = $EndpointMapperPort
            PortType     = 'EndpointMapper'
        }
    }
}

$allResults = New-Object System.Collections.ArrayList
$empResults = @()
if ($empTargets) {
    Write-Log "Phase 1: testing TCP/$EndpointMapperPort (RPC Endpoint Mapper)..." -Level 'INFO'
    $empResults = Invoke-ParallelPortTest -Targets $empTargets -TimeoutMs $TimeoutMs `
                    -ThrottleLimit $ThrottleLimit -TestScript $tcpTestScript
    foreach ($r in $empResults) {
        [void]$allResults.Add($r)
        $lvl = if ($r.Status -eq 'Open') { 'OK' } else { 'WARN' }
        Write-Log ("  {0} ({1}) TCP/{2} => {3} ({4}ms)" -f `
            $r.ComputerName, $r.ResolvedIP, $r.Port, $r.Status, $r.ResponseTimeMs) -Level $lvl
    }
}
else {
    Write-Log "No resolvable hosts to test." -Level 'ERROR'
}

# --- Phase 2: discover + test dynamic RPC ports ------------------------------
$portQryExe = Get-PortQryExe -ExplicitPath $PortQryPath
if (-not $portQryExe) {
    Write-Log "PortQry.exe not found - skipping dynamic-port discovery. TCP/135 results still valid." -Level 'WARN'
    Write-Log "Download PortQryV2 from the Microsoft Download Center and re-run for dynamic-port validation." -Level 'WARN'
}
else {
    Write-Log "Using PortQry: $portQryExe" -Level 'INFO'
    $openEmp = $empResults | Where-Object { $_.Status -eq 'Open' }

    $dynamicTargets = New-Object System.Collections.ArrayList
    foreach ($e in $openEmp) {
        try {
            $dynPorts = Get-EndpointMapperPorts -PortQryExe $portQryExe -ComputerName $e.ComputerName -Port $EndpointMapperPort
            if ($dynPorts.Count -gt 0) {
                Write-Log ("  {0}: endpoint mapper registered {1} dynamic port(s): {2}" -f `
                    $e.ComputerName, $dynPorts.Count, (($dynPorts | Sort-Object) -join ', ')) -Level 'INFO'
                foreach ($p in $dynPorts) {
                    [void]$dynamicTargets.Add([pscustomobject]@{
                        ComputerName = $e.ComputerName
                        ResolvedIP   = $e.ResolvedIP
                        Port         = $p
                        PortType     = 'DynamicRPC'
                    })
                }
            }
            else {
                Write-Log "  $($e.ComputerName): endpoint mapper returned no TCP dynamic ports." -Level 'WARN'
            }
        }
        catch {
            Write-Log "  $($e.ComputerName): PortQry enumeration failed - $($_.Exception.Message)" -Level 'ERROR'
        }
    }

    if ($dynamicTargets.Count -gt 0) {
        Write-Log "Phase 2: testing $($dynamicTargets.Count) discovered dynamic RPC port(s)..." -Level 'INFO'
        $dynResults = Invoke-ParallelPortTest -Targets $dynamicTargets -TimeoutMs $TimeoutMs `
                        -ThrottleLimit $ThrottleLimit -TestScript $tcpTestScript
        foreach ($r in $dynResults) {
            [void]$allResults.Add($r)
            $lvl = if ($r.Status -eq 'Open') { 'OK' } else { 'WARN' }
            Write-Log ("  {0} TCP/{1} (dynamic) => {2} ({3}ms)" -f `
                $r.ComputerName, $r.Port, $r.Status, $r.ResponseTimeMs) -Level $lvl
        }
    }
}

#endregion

#region Output + Summary -----------------------------------------------------

$allResults |
    Sort-Object ComputerName, PortType, Port |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Log "Results exported to: $csvPath" -Level 'INFO'

Write-Host ""
Write-Host "===== SUMMARY =====" -ForegroundColor Cyan
$summary = foreach ($h in $hosts) {
    $rows    = $allResults | Where-Object { $_.ComputerName -eq $h.ComputerName }
    $emp     = $rows | Where-Object { $_.PortType -eq 'EndpointMapper' } | Select-Object -First 1
    $dyn     = $rows | Where-Object { $_.PortType -eq 'DynamicRPC' }
    $dynOpen = @($dyn | Where-Object { $_.Status -eq 'Open' }).Count

    [pscustomobject]@{
        ComputerName    = $h.ComputerName
        ResolvedIP      = if ($h.ResolvedIP) { $h.ResolvedIP } else { 'DNS FAILED' }
        'TCP/135'       = if ($emp) { $emp.Status } else { 'Not tested' }
        DynamicTested   = @($dyn).Count
        DynamicOpen     = $dynOpen
        Result          = if (-not $h.ResolvedIP)          { 'FAIL - DNS' }
                          elseif (-not $emp -or $emp.Status -ne 'Open') { 'FAIL - 135 blocked' }
                          elseif (@($dyn).Count -eq 0)     { 'PARTIAL - 135 only (no PortQry / no dyn ports)' }
                          elseif ($dynOpen -eq @($dyn).Count) { 'PASS' }
                          else { 'FAIL - dynamic port(s) blocked' }
    }
}
$summary | Format-Table -AutoSize

Write-Log "===== CA RPC connectivity check completed =====" -Level 'INFO'
Write-Host "Log:  $logPath" -ForegroundColor Gray
Write-Host "CSV:  $csvPath" -ForegroundColor Gray

#endregion
