function Get-DiagRoleCitrix {
    <#
    .SYNOPSIS
        Collect Citrix VDA service state, registration data, and event channel summary.

    .DESCRIPTION
        Detect Citrix by enumerating services whose Name matches Citrix* (or equals
        BrokerAgent) OR the presence of HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent.
        When detected, write a service table, project VDA registration state from
        the registry (RegistrationState, ListOfDDCs, SiteName, MachineCatalogName,
        DeliveryGroupName), and produce a per-channel event count summary across
        Citrix-named channels filtered through Get-WinEvent -ListLog.

    .PARAMETER WorkingDirectory
        Absolute path to the bundle staging directory. Artifacts write under
        raw\role_specific beneath it.

    .PARAMETER WindowHours
        Lookback window in hours for the Citrix event channel summary. Default 24.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        $r = Get-DiagRoleCitrix -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle1' -WindowHours 24

    .NOTES
        Detection signal: any service whose Name matches Citrix* or equals
        BrokerAgent, OR HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent. When neither is
        present, return Success=$true with empty Artifacts. This is "not applicable",
        not failure.

        VDA state is read from HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent: ListOfDDCs
        (broker address), SiteName, MachineCatalogName, DeliveryGroupName, and
        RegistrationState. policy_engine_running is set only when CitrixCseEngine
        or CitrixPolicyEngine service evidence is available.

        Event summary enumerates Get-WinEvent -ListLog * and intersects with the
        candidate channel list ('Citrix Delivery Services', 'Citrix Broker Service',
        'Citrix Configuration Logging Service'). Empty channels return zero counts
        rather than errors.

        Artifacts written under raw/role_specific/:
          - raw/role_specific/citrix_services.txt
          - raw/role_specific/citrix_vda_state.json
          - raw/role_specific/citrix_event_summary.json

        Get-DiagRoles is the dispatcher and is responsible for calling this only when
        the role is detected; this collector also self-checks defensively and returns
        a no-op result when Citrix is absent.

        The collector never throws. Per-artifact failures append to Errors with
        severity 'warning'. On fatal abort it returns Success=$false with populated
        Errors.
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
        $vdaRegPath = 'HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent'
        $citrixPolicyPath = 'HKLM:\SOFTWARE\Policies\Citrix'

        $citrixServices = @()
        try {
            $citrixServices = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -like 'Citrix*' -or $_.Name -eq 'BrokerAgent'
            })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; reason = "Get-Service enumeration failed: $($_.Exception.Message)"; severity = 'warning' }
        }

        $vdaRegPresent = Test-Path -LiteralPath $vdaRegPath -ErrorAction SilentlyContinue

        if ($citrixServices.Count -eq 0 -and -not $vdaRegPresent) {
            $result.Success = $true
            return $result
        }

        $rawDir = Join-Path $WorkingDirectory 'raw\role_specific'
        if (-not (Test-Path -LiteralPath $rawDir)) {
            try { New-Item -ItemType Directory -Path $rawDir -Force | Out-Null } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; reason = "Could not create raw\role_specific: $($_.Exception.Message)"; severity = 'error' }
            }
        }

        $svcTxtPath = Join-Path $rawDir 'citrix_services.txt'
        try {
            $svcTable = $citrixServices |
                Select-Object Name, Status, StartType |
                Sort-Object Name |
                Format-Table -AutoSize |
                Out-String -Width 200
            [System.IO.File]::WriteAllText($svcTxtPath, $svcTable, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path        = 'raw/role_specific/citrix_services.txt'
                category    = 'role_citrix_services'
                type        = 'raw'
                description = 'Citrix-related services (Citrix*, BrokerAgent) with Status and StartType'
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; artifact = 'raw/role_specific/citrix_services.txt'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $vdaState = [ordered]@{
            registered_with_broker = $null
            broker_address         = $null
            site_name              = $null
            machine_catalog        = $null
            delivery_group         = $null
            policy_engine_running  = $null
        }

        if ($vdaRegPresent) {
            try {
                $vdaProps = Get-ItemProperty -LiteralPath $vdaRegPath -ErrorAction Stop
                if ($vdaProps.PSObject.Properties.Name -contains 'ListOfDDCs') { $vdaState.broker_address  = "$($vdaProps.ListOfDDCs)" }
                if ($vdaProps.PSObject.Properties.Name -contains 'SiteName')   { $vdaState.site_name       = "$($vdaProps.SiteName)" }
                if ($vdaProps.PSObject.Properties.Name -contains 'MachineCatalogName') { $vdaState.machine_catalog = "$($vdaProps.MachineCatalogName)" }
                if ($vdaProps.PSObject.Properties.Name -contains 'DeliveryGroupName')  { $vdaState.delivery_group  = "$($vdaProps.DeliveryGroupName)" }
                if ($vdaProps.PSObject.Properties.Name -contains 'RegistrationState') {
                    $vdaState.registered_with_broker = ([string]$vdaProps.RegistrationState -eq 'Registered')
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; artifact = 'raw/role_specific/citrix_vda_state.json'; reason = "Read $vdaRegPath failed: $($_.Exception.Message)"; severity = 'warning' }
            }
        }

        try {
            if (Test-Path -LiteralPath $citrixPolicyPath -ErrorAction SilentlyContinue) {
                # Presence of policy key alone does not confirm engine running; leave $null unless service evidence available.
            }
            $policySvc = $citrixServices | Where-Object { $_.Name -eq 'CitrixCseEngine' -or $_.Name -eq 'CitrixPolicyEngine' } | Select-Object -First 1
            if ($policySvc) {
                $vdaState.policy_engine_running = ([string]$policySvc.Status -eq 'Running')
            }
        } catch { }

        $vdaStateJsonPath = Join-Path $rawDir 'citrix_vda_state.json'
        try {
            $vdaStateDoc = [ordered]@{
                schema_version = '1.0'
                host           = @{ computer_name = $env:COMPUTERNAME }
                collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                data           = $vdaState
            }
            $json = $vdaStateDoc | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($vdaStateJsonPath, $json, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path           = 'raw/role_specific/citrix_vda_state.json'
                category       = 'role_citrix_vda_state'
                schema_version = '1.0'
                type           = 'derived'
                description    = 'VDA registration, broker, site, catalog, delivery group, policy engine state'
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; artifact = 'raw/role_specific/citrix_vda_state.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $candidateChannels = @(
            'Citrix Delivery Services',
            'Citrix Broker Service',
            'Citrix Configuration Logging Service'
        )
        $eventSummary = @()
        $sinceUtc = (Get-Date).ToUniversalTime().AddHours(-1 * [math]::Abs($WindowHours))
        $sinceLocal = $sinceUtc.ToLocalTime()

        $existingChannels = @()
        try {
            $existingChannels = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
                Where-Object { $candidateChannels -contains $_.LogName } |
                ForEach-Object { $_.LogName })
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; artifact = 'raw/role_specific/citrix_event_summary.json'; reason = "Get-WinEvent -ListLog failed: $($_.Exception.Message)"; severity = 'warning' }
        }

        foreach ($ch in $existingChannels) {
            $entry = [ordered]@{
                channel        = $ch
                total          = 0
                error_count    = 0
                warning_count  = 0
            }
            try {
                $events = @(Get-WinEvent -FilterHashtable @{ LogName = $ch; StartTime = $sinceLocal } -ErrorAction Stop)
                $entry.total         = $events.Count
                $entry.error_count   = @($events | Where-Object { [int]$_.Level -eq 2 }).Count
                $entry.warning_count = @($events | Where-Object { [int]$_.Level -eq 3 }).Count
            } catch {
                # Empty channel raises a non-fatal "no events match" -- record zeros and continue.
                if ($_.Exception.Message -notmatch 'No events were found') {
                    $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; artifact = 'raw/role_specific/citrix_event_summary.json'; reason = "Read channel '$ch' failed: $($_.Exception.Message)"; severity = 'warning' }
                }
            }
            $eventSummary += $entry
        }

        $eventJsonPath = Join-Path $rawDir 'citrix_event_summary.json'
        try {
            $evtDoc = [ordered]@{
                schema_version = '1.0'
                host           = @{ computer_name = $env:COMPUTERNAME }
                collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                window_hours   = $WindowHours
                events_from_utc = $sinceUtc.ToString($fmt)
                data           = @{ channels = $eventSummary }
            }
            $json = $evtDoc | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($eventJsonPath, $json, [System.Text.UTF8Encoding]::new($false))
            $result.Artifacts += @{
                path           = 'raw/role_specific/citrix_event_summary.json'
                category       = 'role_citrix_events'
                schema_version = '1.0'
                type           = 'derived'
                description    = "Per-channel event counts (total/error/warning) for last $WindowHours hours across present Citrix channels"
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleCitrix'; artifact = 'raw/role_specific/citrix_event_summary.json'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{
            collector = 'Get-DiagRoleCitrix'
            reason    = $_.Exception.Message
            severity  = 'error'
        }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
