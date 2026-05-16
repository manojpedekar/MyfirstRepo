function Get-DiagRoleDFSR {
    <#
    .SYNOPSIS
        Collect DFSR replicated folder state, connection state, and replication health.

    .DESCRIPTION
        Detect DFSR by checking for the DFSR service. When present, query CIM
        namespace root\MicrosoftDfs for DfsrReplicatedFolderInfo and DfsrConnectionInfo,
        then run dfsrdiag.exe replicationstate /v and capture its output. Resolve
        dfsrdiag.exe from PATH first; fall back to $env:windir\system32\dfsrdiag.exe.
        When neither resolves, log an info-level skip and continue.

    .PARAMETER WorkingDirectory
        Absolute path to the bundle staging directory. Artifacts write under
        raw\role_specific\dfsr and raw\role_specific\dfsr_health.xml beneath it.

    .PARAMETER WindowHours
        Lookback window in hours. Reserved for future event channel filtering;
        default 24.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        $r = Get-DiagRoleDFSR -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle1'

    .NOTES
        Detection signal: presence of the DFSR Windows service. When absent, return
        Success=$true with empty Artifacts. This is "not applicable", not failure.

        Folder and connection data come from CIM namespace root\MicrosoftDfs
        (classes DfsrReplicatedFolderInfo and DfsrConnectionInfo). Health output
        comes from dfsrdiag.exe replicationstate /v; the collector resolves the
        executable from PATH and falls back to $env:windir\system32\dfsrdiag.exe.
        A missing dfsrdiag.exe records an info-level Errors entry rather than a
        warning, since the artifact is optional.

        Artifacts written under raw/role_specific/:
          - raw/role_specific/dfsr/replicated_folders.json
          - raw/role_specific/dfsr/connections.json
          - raw/role_specific/dfsr_health.xml  (dfsrdiag text output, .xml extension
            preserved for layout consistency with the architecture overview)

        Get-DiagRoles is the dispatcher and is responsible for calling this only when
        the role is detected; this collector also self-checks defensively and returns
        a no-op result when the DFSR service is absent.

        The collector never throws. Per-artifact failures append to Errors with
        severity 'warning' (or 'info' for the missing dfsrdiag.exe case). On fatal
        abort it returns Success=$false with populated Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    try {
        $svc = Get-Service -Name 'DFSR' -ErrorAction SilentlyContinue
        if (-not $svc) {
            $result.Success = $true
            return $result
        }

        $rawDir = Join-Path $WorkingDirectory 'raw\role_specific\dfsr'
        if (-not (Test-Path $rawDir)) {
            try { New-Item -Path $rawDir -ItemType Directory -Force | Out-Null } catch { }
        }

        $replicatedFolders = @()
        try {
            $replicatedFolders = @(Get-CimInstance -Namespace 'root\MicrosoftDfs' -ClassName 'DfsrReplicatedFolderInfo' -ErrorAction Stop | ForEach-Object {
                [ordered]@{
                    replication_group_name    = "$($_.ReplicationGroupName)"
                    replicated_folder_name    = "$($_.ReplicatedFolderName)"
                    state                     = [int]$_.State
                    conflict_size_in_bytes    = [int64]$_.ConflictSizeInBytes
                    deleted_size_in_bytes     = [int64]$_.DeletedSizeInBytes
                    conflict_files            = [int64]$_.ConflictFiles
                    deleted_files             = [int64]$_.DeletedFiles
                }
            })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleDFSR'; artifact = 'raw/role_specific/dfsr/replicated_folders.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $rfData = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                replicated_folders = $replicatedFolders
                count              = $replicatedFolders.Count
            }
        }

        $rfPath = Join-Path $rawDir 'replicated_folders.json'
        try {
            $json = $rfData | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($rfPath, $json, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/role_specific/dfsr/replicated_folders.json'
                category    = 'dfsr_replicated_folders'
                type        = 'raw'
                description = 'DfsrReplicatedFolderInfo WMI snapshot'
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleDFSR'; artifact = 'raw/role_specific/dfsr/replicated_folders.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $connections = @()
        try {
            $connections = @(Get-CimInstance -Namespace 'root\MicrosoftDfs' -ClassName 'DfsrConnectionInfo' -ErrorAction Stop | ForEach-Object {
                $lastChange = $null
                if ($_.LastChangeCommunicationTime) {
                    try { $lastChange = ([datetime]$_.LastChangeCommunicationTime).ToUniversalTime().ToString($fmt) } catch { $lastChange = $null }
                }
                [ordered]@{
                    name                            = "$($_.Name)"
                    partner_name                    = "$($_.PartnerName)"
                    state                           = [int]$_.State
                    last_change_communication_time  = $lastChange
                }
            })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleDFSR'; artifact = 'raw/role_specific/dfsr/connections.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $connData = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                connections = $connections
                count       = $connections.Count
            }
        }

        $connPath = Join-Path $rawDir 'connections.json'
        try {
            $json = $connData | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($connPath, $json, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/role_specific/dfsr/connections.json'
                category    = 'dfsr_connections'
                type        = 'raw'
                description = 'DfsrConnectionInfo WMI snapshot'
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleDFSR'; artifact = 'raw/role_specific/dfsr/connections.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $dfsrdiag = $null
        try {
            $cmd = Get-Command 'dfsrdiag.exe' -ErrorAction SilentlyContinue
            if ($cmd) { $dfsrdiag = $cmd.Source }
        } catch { }
        if (-not $dfsrdiag) {
            $fallback = Join-Path $env:windir 'system32\dfsrdiag.exe'
            if (Test-Path $fallback) { $dfsrdiag = $fallback }
        }

        if ($dfsrdiag) {
            $healthPath = Join-Path $WorkingDirectory 'raw\role_specific\dfsr_health.xml'
            try {
                $text = & $dfsrdiag 'replicationstate' '/v' 2>&1
                [System.IO.File]::WriteAllText($healthPath, ($text -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
                $result.Artifacts += @{
                    path        = 'raw/role_specific/dfsr_health.xml'
                    category    = 'dfsr_health'
                    type        = 'raw'
                    description = 'dfsrdiag.exe replicationstate /v output'
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleDFSR'; artifact = 'raw/role_specific/dfsr_health.xml'; reason = $_.Exception.Message; severity = 'warning' }
            }
        } else {
            $result.Errors += @{ collector = 'Get-DiagRoleDFSR'; artifact = 'raw/role_specific/dfsr_health.xml'; reason = 'dfsrdiag.exe not found on PATH or in system32'; severity = 'info' }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{
            collector = 'Get-DiagRoleDFSR'
            reason    = $_.Exception.Message
            severity  = 'error'
        }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
