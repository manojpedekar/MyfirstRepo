<#
.SYNOPSIS
    Collects forensic evidence explaining a transient SQL "transport-level"
    connection failure that affected multiple client (agent) servers at once.

.DESCRIPTION
    Built for the BAMM / ASPYKTOTSSQL2 incident of 2026-07-22 ~19:34 EST, but
    fully parameterized for any "SQL suddenly unreachable from many clients"
    event.

    A transport-level SQL error means the TCP session to SQL was reset / dropped
    / timed out. When it hits ALL clients simultaneously the cause is at a shared
    point: the SQL host itself (reboot, failover, service stop, resource
    exhaustion) or the shared network path. This script pulls, from the SQL host
    AND every affected client, the specific Windows/SQL evidence that confirms or
    eliminates each of those causes, scoped to a time window around the incident.

    It is READ-ONLY and safe to run against production. It changes nothing on the
    target servers; it only reads event logs, WMI, the registry (for the SQL log
    path), and the SQL ERRORLOG files.

    Evidence collected per server:
      * Current state          - last boot, uptime, OS, RAM, per-volume free space
      * Reboot / shutdown       - 1074, 1076, 6005, 6006, 6008, 6013, 41 (Kernel-Power),
                                  1001 (BugCheck)
      * Service state changes   - 7031/7034/7036/7040 filtered to SQL + BAMM services
      * SQL engine errors        - Application-log MSSQL* events (17xx, 833, 9002,
                                  17883/17884 non-yielding scheduler, 701, 18456, etc.)
      * Windows Update activity  - WindowsUpdateClient 19/43/44 (patch install = reboot)
      * Storage / disk errors    - disk 7/11/15/51, Ntfs, volsnap
      * Network errors           - Tcpip 4227/4231/4266 (port exhaustion), NIC link events
      * Failover Cluster events  - 1069/1135/1146/1177/1230 (if the cluster log exists)
      * SQL ERRORLOG parse       - (SQL host only) reads ERRORLOG files and returns lines
                                  inside the window

    Output: one CSV per evidence category (all servers combined), one raw per-server
    text dump, and a consolidated log, all under -OutputFolder.

.PARAMETER SqlServer
    FQDN/hostname of the SQL server that clients failed to reach.
    Default: ASPYKTOTSSQL2.sscdirect.com

.PARAMETER ClientServer
    One or more client / agent servers that lost connectivity.
    Default: the three BAMM agent hosts from the incident.

.PARAMETER IncidentTime
    Approximate incident time. Default: 2026-07-22 19:34 (local time of the server
    running this script). If your servers are in a different timezone than the
    incident report, pass the time in the TARGET servers' local time.

.PARAMETER HoursBefore
    Hours of history to pull before IncidentTime. Default: 3.

.PARAMETER HoursAfter
    Hours of history to pull after IncidentTime. Default: 2.

.PARAMETER OutputFolder
    Where evidence is written. Default: C:\temp\SQL_Incident_Evidence

.PARAMETER Credential
    Optional PSCredential for remoting to the target servers.

.PARAMETER Sequential
    Force sequential collection (no parallel jobs). Use for maximum compatibility
    or when troubleshooting the script itself.

.EXAMPLE
    .\Get-SqlConnectivityIncidentEvidence_v1.ps1

    Runs the BAMM/ASPYKTOTSSQL2 07-22 investigation with defaults.

.EXAMPLE
    .\Get-SqlConnectivityIncidentEvidence_v1.ps1 -IncidentTime '2026-07-22 19:34' -HoursBefore 6 -Credential (Get-Credential)

.NOTES
    Requirements
      * PowerShell 3.0+ on the machine running the script (uses Get-WinEvent
        -FilterHashtable and background jobs). Targets can be WS2008 R2+.
      * PowerShell Remoting (WinRM) enabled on the target servers, OR run each
        server locally.
      * Account with permission to read event logs and the SQL Log directory on
        the targets (local admin is simplest).
    Design choices
      * Uses Get-WmiObject (not CIM) for system info so the remote scriptblock
        stays compatible back to WS2008 R2.
      * Every Get-WinEvent query is wrapped in try/catch because Get-WinEvent
        throws a terminating error when zero events match the filter.
    Limitation
      * If the SQL service restarted enough times since the incident, the relevant
        ERRORLOG may have already cycled out (default = 6 files). Windows event
        logs are the more durable source.
#>

[CmdletBinding()]
param(
    [string]   $SqlServer     = 'ASPYKTOTSSQL2.sscdirect.com',

    [string[]] $ClientServer  = @(
        'ASPOTS4.sscdirect.com',
        'ASPOTS5.sscdirect.com',
        'ASPOSTSQL1.sscdirect.com'
    ),

    [datetime] $IncidentTime  = '2026-07-22 19:34:00',

    [ValidateRange(0, 72)]
    [int]      $HoursBefore   = 3,

    [ValidateRange(0, 72)]
    [int]      $HoursAfter    = 2,

    [string]   $OutputFolder  = 'C:\temp\SQL_Incident_Evidence',

    [System.Management.Automation.PSCredential] $Credential,

    [switch]   $Sequential
)

#region ----------------------------- Setup -----------------------------------

$ErrorActionPreference = 'Stop'
$TimeStampFormat       = 'yyyy-MM-dd HH:mm:ss'
$RunStamp              = (Get-Date).ToString('yyyyMMdd_HHmmss')
$StartTime             = $IncidentTime.AddHours(-$HoursBefore)
$EndTime               = $IncidentTime.AddHours($HoursAfter)

# SqlServer first (it is the prime suspect), then the affected clients. De-duplicate.
$AllServers = @($SqlServer) + $ClientServer | Where-Object { $_ } | Select-Object -Unique

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $OutputFolder ("Collection_{0}.log" -f $RunStamp)

function Write-Log {
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string] $Level = 'INFO'
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date).ToString($TimeStampFormat), $Level, $Message
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line -ForegroundColor Cyan }
    }
    Add-Content -Path $LogFile -Value $line
}

Write-Log "=== SQL connectivity incident evidence collection started ==="
Write-Log ("Incident time : {0}" -f $IncidentTime.ToString($TimeStampFormat))
Write-Log ("Search window  : {0}  ->  {1}" -f $StartTime.ToString($TimeStampFormat), $EndTime.ToString($TimeStampFormat))
Write-Log ("SQL server     : {0}" -f $SqlServer)
Write-Log ("Client servers : {0}" -f ($ClientServer -join ', '))
Write-Log ("Output folder  : {0}" -f $OutputFolder)

#endregion

#region ------------------- Remote collection scriptblock ----------------------

# This block runs ON each target server. It returns a single PSCustomObject whose
# properties are arrays of evidence rows, so the caller can split them by category.
$CollectionScript = {
    param($StartTime, $EndTime, $IsSqlHost)

    $server = $env:COMPUTERNAME

    # Safe Get-WinEvent wrapper: returns @() instead of throwing on "no events".
    function Get-Events {
        param([hashtable]$Filter)
        try {
            Get-WinEvent -FilterHashtable $Filter -ErrorAction Stop |
                ForEach-Object {
                    [PSCustomObject]@{
                        Server       = $server
                        TimeCreated  = $_.TimeCreated
                        LogName      = $_.LogName
                        Source       = $_.ProviderName
                        Id           = $_.Id
                        Level        = $_.LevelDisplayName
                        Message      = ($_.Message -replace '\s+', ' ').Trim()
                    }
                }
        }
        catch {
            # "No events were found" is expected and not an error.
            if ($_.Exception.Message -notmatch 'No events were found') {
                [PSCustomObject]@{
                    Server = $server; TimeCreated = $null; LogName = $Filter.LogName
                    Source = 'COLLECTION-ERROR'; Id = 0; Level = 'Error'
                    Message = "Query failed: $($_.Exception.Message)"
                }
            }
        }
    }

    # ---- Current system state (WMI = WS2008R2-compatible) ----
    $systemState = $null
    try {
        $os   = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $cs   = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        $boot = $os.ConvertToDateTime($os.LastBootUpTime)
        $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
            ForEach-Object {
                "{0} {1}GB free / {2}GB ({3}% free)" -f $_.DeviceID,
                    [math]::Round($_.FreeSpace/1GB,1),
                    [math]::Round($_.Size/1GB,1),
                    [math]::Round(($_.FreeSpace/$_.Size)*100,0)
            }
        $systemState = [PSCustomObject]@{
            Server          = $server
            OS              = $os.Caption
            LastBootUpTime  = $boot
            UptimeHours     = [math]::Round(((Get-Date) - $boot).TotalHours, 1)
            RebootAfterStart= ($boot -gt $StartTime)   # <-- did this box reboot inside the window?
            TotalRAM_GB     = [math]::Round($cs.TotalPhysicalMemory/1GB, 1)
            FreeRAM_GB      = [math]::Round($os.FreePhysicalMemory/1MB, 1)
            Disks           = ($disks -join ' | ')
        }
    }
    catch {
        $systemState = [PSCustomObject]@{
            Server = $server; OS = "WMI ERROR: $($_.Exception.Message)"
            LastBootUpTime = $null; UptimeHours = $null; RebootAfterStart = $null
            TotalRAM_GB = $null; FreeRAM_GB = $null; Disks = $null
        }
    }

    # ---- Reboot / shutdown / crash (System log) ----
    $reboots = Get-Events @{
        LogName   = 'System'
        Id        = 1074, 1076, 6005, 6006, 6008, 6013, 41, 1001
        StartTime = $StartTime
        EndTime   = $EndTime
    }

    # ---- Service state changes, then filter to SQL + BAMM services ----
    $svcAll = Get-Events @{
        LogName   = 'System'
        Id        = 7031, 7034, 7036, 7040, 7000, 7009, 7011
        StartTime = $StartTime
        EndTime   = $EndTime
    }
    $services = $svcAll | Where-Object { $_.Message -match '(?i)SQL|MSSQL|BAMM|Cluster' }

    # ---- SQL engine errors (Application log, any MSSQL* source) ----
    $sqlAppErrors = Get-Events @{
        LogName   = 'Application'
        StartTime = $StartTime
        EndTime   = $EndTime
    } | Where-Object { $_.Source -match '(?i)MSSQL|SQLSERVERAGENT|BAMM' }

    # ---- Windows Update activity (patch install strongly implies a reboot) ----
    $windowsUpdate = Get-Events @{
        LogName   = 'System'
        Id        = 19, 20, 43, 44
        StartTime = $StartTime
        EndTime   = $EndTime
    } | Where-Object { $_.Source -match '(?i)WindowsUpdateClient' }

    # ---- Storage / disk errors (System log) ----
    $storage = Get-Events @{
        LogName   = 'System'
        Id        = 7, 9, 11, 15, 51, 129, 153
        StartTime = $StartTime
        EndTime   = $EndTime
    }

    # ---- Network errors: TCP port exhaustion + NIC link events ----
    $network = Get-Events @{
        LogName   = 'System'
        Id        = 4227, 4231, 4266, 27, 4201, 4202
        StartTime = $StartTime
        EndTime   = $EndTime
    }

    # ---- Failover cluster events (only if the log exists) ----
    $cluster = @()
    try {
        if (Get-WinEvent -ListLog 'Microsoft-Windows-FailoverClustering/Operational' -ErrorAction Stop) {
            $cluster = Get-Events @{
                LogName   = 'Microsoft-Windows-FailoverClustering/Operational'
                StartTime = $StartTime
                EndTime   = $EndTime
            }
            $cluster += Get-Events @{
                LogName   = 'System'
                Id        = 1069, 1135, 1146, 1177, 1230, 1205, 1254
                StartTime = $StartTime
                EndTime   = $EndTime
            }
        }
    }
    catch { }

    # ---- SQL ERRORLOG file parse (SQL host only) ----
    $sqlErrorLog = @()
    if ($IsSqlHost) {
        try {
            # Discover every instance's ERRORLOG path from the registry.
            $instRoot = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
            $logPaths = @()
            if (Test-Path $instRoot) {
                $instances = Get-Item $instRoot
                foreach ($instName in $instances.GetValueNames()) {
                    $instId = $instances.GetValue($instName)
                    $paramKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instId\MSSQLServer\Parameters"
                    if (Test-Path $paramKey) {
                        $args = Get-Item $paramKey
                        foreach ($v in $args.GetValueNames()) {
                            $val = $args.GetValue($v)
                            if ($val -match '^-e(.+ERRORLOG)$') {
                                $logPaths += $matches[1]
                            }
                        }
                    }
                }
            }
            # Fallback to the default instance path if registry discovery found nothing.
            if (-not $logPaths) {
                $logPaths = Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse -Filter 'ERRORLOG' -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }

            foreach ($base in ($logPaths | Select-Object -Unique)) {
                $dir = Split-Path $base -Parent
                # ERRORLOG (current) + ERRORLOG.1..6 (archives)
                $files = Get-ChildItem -Path $dir -Filter 'ERRORLOG*' -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $StartTime }
                foreach ($f in $files) {
                    # SQL ERRORLOG timestamp format: "2026-07-22 19:34:07.12 ..."
                    Get-Content -Path $f.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                        if ($_ -match '^(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})') {
                            $ts = $null
                            if ([datetime]::TryParse($matches[1], [ref]$ts)) {
                                if ($ts -ge $StartTime -and $ts -le $EndTime) {
                                    $sqlErrorLog += [PSCustomObject]@{
                                        Server = $server; File = $f.Name
                                        TimeCreated = $ts; Line = $_.Trim()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            $sqlErrorLog += [PSCustomObject]@{
                Server = $server; File = 'ERROR'; TimeCreated = $null
                Line = "ERRORLOG parse failed: $($_.Exception.Message)"
            }
        }
    }

    # Return everything as one object.
    [PSCustomObject]@{
        Server        = $server
        SystemState   = $systemState
        Reboots       = $reboots
        Services      = $services
        SqlAppErrors  = $sqlAppErrors
        WindowsUpdate = $windowsUpdate
        Storage       = $storage
        Network       = $network
        Cluster       = $cluster
        SqlErrorLog   = $sqlErrorLog
    }
}

#endregion

#region --------------------------- Execution ----------------------------------

$icmCommon = @{ ScriptBlock = $CollectionScript }
if ($Credential) { $icmCommon['Credential'] = $Credential }

$results = @()

if ($Sequential -or $AllServers.Count -eq 1) {
    foreach ($srv in $AllServers) {
        Write-Log "Collecting from $srv ..."
        try {
            $isSql = ($srv -eq $SqlServer)
            $results += Invoke-Command @icmCommon -ComputerName $srv `
                -ArgumentList $StartTime, $EndTime, $isSql
            Write-Log "  ...done: $srv"
        }
        catch {
            Write-Log "  FAILED to reach $srv : $($_.Exception.Message)" -Level ERROR
        }
    }
}
else {
    # Parallel via Invoke-Command fan-out. Invoke-Command runs all named computers
    # concurrently and tags each result with PSComputerName.
    Write-Log ("Collecting from {0} servers in parallel..." -f $AllServers.Count)
    foreach ($srv in $AllServers) {
        $isSql = ($srv -eq $SqlServer)
        try {
            $results += Invoke-Command @icmCommon -ComputerName $srv `
                -ArgumentList $StartTime, $EndTime, $isSql -AsJob -JobName $srv | Out-Null
        }
        catch {
            Write-Log "  FAILED to queue $srv : $($_.Exception.Message)" -Level ERROR
        }
    }
    $results = @()
    Get-Job | Wait-Job | Out-Null
    foreach ($job in Get-Job) {
        try {
            $r = Receive-Job $job -ErrorAction Stop
            if ($r) { $results += $r }
            Write-Log "  ...done: $($job.Name) [$($job.State)]"
        }
        catch {
            Write-Log "  FAILED $($job.Name): $($_.Exception.Message)" -Level ERROR
        }
        Remove-Job $job -Force
    }
}

if (-not $results) {
    Write-Log "No results collected from any server. Check remoting/credentials." -Level ERROR
    return
}

#endregion

#region ---------------------- Export & summarize ------------------------------

function Export-Category {
    param([string]$Name, [object[]]$Rows)
    $rows = $Rows | Where-Object { $_ }
    if ($rows) {
        $path = Join-Path $OutputFolder ("{0}_{1}.csv" -f $Name, $RunStamp)
        $rows | Sort-Object Server, TimeCreated | Export-Csv -Path $path -NoTypeInformation -Force
        Write-Log ("  {0,-16}: {1,4} rows -> {2}" -f $Name, $rows.Count, (Split-Path $path -Leaf))
    }
    else {
        Write-Log ("  {0,-16}:    0 rows (none found)" -f $Name)
    }
}

Write-Log "Exporting evidence categories..."
Export-Category 'SystemState'   ($results.SystemState)
Export-Category 'Reboots'       ($results.Reboots)
Export-Category 'Services'      ($results.Services)
Export-Category 'SqlAppErrors'  ($results.SqlAppErrors)
Export-Category 'WindowsUpdate' ($results.WindowsUpdate)
Export-Category 'Storage'       ($results.Storage)
Export-Category 'Network'       ($results.Network)
Export-Category 'Cluster'       ($results.Cluster)
Export-Category 'SqlErrorLog'   ($results.SqlErrorLog)

# ---- Consolidated, human-readable findings summary ----
$summaryPath = Join-Path $OutputFolder ("_SUMMARY_{0}.txt" -f $RunStamp)
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("SQL CONNECTIVITY INCIDENT - EVIDENCE SUMMARY")
[void]$sb.AppendLine("Generated       : $((Get-Date).ToString($TimeStampFormat))")
[void]$sb.AppendLine("Incident time   : $($IncidentTime.ToString($TimeStampFormat))")
[void]$sb.AppendLine("Search window   : $($StartTime.ToString($TimeStampFormat)) -> $($EndTime.ToString($TimeStampFormat))")
[void]$sb.AppendLine("SQL server      : $SqlServer")
[void]$sb.AppendLine("Client servers  : $($ClientServer -join ', ')")
[void]$sb.AppendLine(("=" * 78))

# Highlight the single most important question: did the SQL host reboot in-window?
[void]$sb.AppendLine("`n>> PRIME SUSPECT CHECK - did any server reboot inside the window?")
foreach ($s in ($results.SystemState | Sort-Object Server)) {
    $flag = if ($s.RebootAfterStart -eq $true) { '  *** REBOOTED IN/AFTER WINDOW ***' } else { '' }
    [void]$sb.AppendLine(("   {0,-28} lastboot={1}  uptime={2}h{3}" -f `
        $s.Server, $s.LastBootUpTime, $s.UptimeHours, $flag))
    [void]$sb.AppendLine(("       RAM free {0}/{1} GB | Disks: {2}" -f $s.FreeRAM_GB, $s.TotalRAM_GB, $s.Disks))
}

$counts = [ordered]@{
    'Reboot/shutdown events' = ($results.Reboots       | Where-Object {$_}).Count
    'SQL/BAMM service events'= ($results.Services       | Where-Object {$_}).Count
    'SQL engine errors'      = ($results.SqlAppErrors    | Where-Object {$_}).Count
    'Windows Update events'  = ($results.WindowsUpdate  | Where-Object {$_}).Count
    'Storage/disk errors'    = ($results.Storage         | Where-Object {$_}).Count
    'Network errors'         = ($results.Network         | Where-Object {$_}).Count
    'Cluster events'         = ($results.Cluster         | Where-Object {$_}).Count
    'SQL ERRORLOG lines'     = ($results.SqlErrorLog     | Where-Object {$_}).Count
}
[void]$sb.AppendLine("`n>> EVIDENCE COUNTS IN WINDOW")
foreach ($k in $counts.Keys) { [void]$sb.AppendLine(("   {0,-26}: {1}" -f $k, $counts[$k])) }

# Surface the closest-to-incident SQL ERRORLOG lines inline (most valuable evidence).
$sqlLines = $results.SqlErrorLog | Where-Object { $_ -and $_.TimeCreated } | Sort-Object TimeCreated
if ($sqlLines) {
    [void]$sb.AppendLine("`n>> SQL ERRORLOG lines nearest the incident:")
    $sqlLines | Select-Object -First 40 | ForEach-Object {
        [void]$sb.AppendLine(("   {0}  {1}" -f $_.TimeCreated.ToString($TimeStampFormat), $_.Line))
    }
}

$sb.ToString() | Set-Content -Path $summaryPath -Encoding UTF8
Write-Log "Summary written: $(Split-Path $summaryPath -Leaf)"

Write-Log "=== Collection complete. Review _SUMMARY_*.txt first, then the CSVs. ==="
Write-Host ""
Get-Content $summaryPath | Write-Host

#endregion
