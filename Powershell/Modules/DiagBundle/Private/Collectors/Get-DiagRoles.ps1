function Get-DiagRoles {
    <#
    .SYNOPSIS
        Detect installed server roles and applications, dispatch to per-role collectors, and aggregate results.

    .DESCRIPTION
        Probes for IIS, SQL Server, Citrix, DFSR, DNS, AD DS, Hyper-V, File Server, and Cloudbase-Init using Get-WindowsFeature, Get-Service presence checks, and install-path probes. Per open item #4, feature/service presence is preferred over registry sniffing. For each of the six roles that has a dedicated collector (iis, sql, citrix, dfsr, hypervisor, cloudbase_init), invokes the role function when present and detected, merges its Artifacts and Errors into the parent result, and records a per-role dispatch entry with ran/success/artifact_count/duration_seconds. Writes the detection map and the dispatch map to summary\roles_apps.json. The hypervisor entry always dispatches because the plugin self-detects platform and emits a stub summary on physical hosts. Cloudbase-Init detection is install-path based and not gated on hypervisor (a converted image can still have cloudbase-init artifacts worth collecting).

    .PARAMETER WorkingDirectory
        Root of the staging tree. Passed through to each dispatched role collector.

    .PARAMETER WindowHours
        Time window in hours, passed through to each dispatched role collector. Defaults to 24.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagRoles -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001' -WindowHours 24

    .NOTES
        Artifacts written:
          summary/roles_apps.json
          plus all artifacts produced by dispatched role collectors:
            Get-DiagRoleIIS
            Get-DiagRoleSQL
            Get-DiagRoleCitrix
            Get-DiagRoleDFSR
            Get-DiagRoleHypervisor

        Detection keys: iis, sql, citrix, dfsr, dns, ad_ds, hyper_v, file_server, hypervisor. Five dispatch to a role collector; the others are recorded for context. The 'hypervisor' detection key is always true (the dispatcher self-detects platform internally and emits a stub summary on physical hosts).

        The collector never throws. On fatal abort it returns Success=$false with populated Errors.
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

    function _SvcExists([string]$pattern) {
        [bool](Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern })
    }
    function _FeatureInstalled([string]$name) {
        try {
            if (Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue) {
                return [bool]((Get-WindowsFeature -Name $name -ErrorAction SilentlyContinue) | Where-Object { $_.Installed })
            }
        } catch { }
        return $false
    }

    try {
        $detected = [ordered]@{
            iis             = (_FeatureInstalled 'Web-Server')   -or (_SvcExists 'W3SVC')
            sql             = _SvcExists 'MSSQL*'
            citrix          = _SvcExists 'BrokerAgent'           -or (_SvcExists 'Citrix*')
            dfsr            = _SvcExists 'DFSR'
            dns             = _SvcExists 'DNS'                   -or (_FeatureInstalled 'DNS')
            ad_ds           = _FeatureInstalled 'AD-Domain-Services'
            hyper_v         = _SvcExists 'vmms'                  -or (_FeatureInstalled 'Hyper-V')
            file_server     = _FeatureInstalled 'File-Services' -or (_SvcExists 'LanmanServer')
            hypervisor      = $true
            cloudbase_init  = (Test-Path -LiteralPath 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init') -or (_SvcExists 'cloudbase-init')
        }

        $dispatched = [ordered]@{}
        $dispatchTable = @(
            @{ Key = 'iis';            Function = 'Get-DiagRoleIIS' }
            @{ Key = 'sql';            Function = 'Get-DiagRoleSQL' }
            @{ Key = 'citrix';         Function = 'Get-DiagRoleCitrix' }
            @{ Key = 'dfsr';           Function = 'Get-DiagRoleDFSR' }
            @{ Key = 'hypervisor';     Function = 'Get-DiagRoleHypervisor' }
            @{ Key = 'cloudbase_init'; Function = 'Get-DiagRoleCloudbaseInit' }
        )

        foreach ($d in $dispatchTable) {
            if (-not $detected[$d.Key]) {
                $dispatched[$d.Key] = @{ ran = $false; reason = 'not detected' }
                continue
            }
            if (-not (Get-Command -Name $d.Function -ErrorAction SilentlyContinue)) {
                $dispatched[$d.Key] = @{ ran = $false; reason = "no collector function: $($d.Function)" }
                continue
            }

            try {
                $r = Invoke-DiagTimed -Collector 'Get-DiagRoles' -Step "dispatch $($d.Function)" -Action {
                    & $d.Function -WorkingDirectory $WorkingDirectory -WindowHours $WindowHours
                }
                $dispatched[$d.Key] = [ordered]@{
                    ran               = $true
                    success           = [bool]$r.Success
                    artifact_count    = ($r.Artifacts | Measure-Object).Count
                    duration_seconds  = [int]$r.DurationSeconds
                }
                foreach ($a in $r.Artifacts) { $result.Artifacts += $a }
                foreach ($e in $r.Errors)    { $result.Errors    += $e }
            } catch {
                $dispatched[$d.Key] = @{ ran = $false; reason = $_.Exception.Message }
                $result.Errors += @{ collector = $d.Function; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        $data = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                detected   = $detected
                dispatched = $dispatched
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\roles_apps.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/roles_apps.json'
            category       = 'roles_apps'
            schema_version = '1.0'
            type           = 'derived'
            description    = 'Detected roles/apps and per-role collector dispatch outcomes'
        }
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagRoles'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
