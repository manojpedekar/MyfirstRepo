function Initialize-DiagManifest {
    <#
    .SYNOPSIS
        Build the in-memory manifest skeleton for a new collection.
    .DESCRIPTION
        Create the ordered hashtable that every collector appends to during
        the run. Invoke-DiagBundle calls this once near the start, after the
        working directory exists. The skeleton holds host identity, OS facts,
        collection metadata, the time window, and empty arrays for artifacts,
        errors, redactions, and size budget. Complete-DiagManifest seals it
        at the end of the run.
    .PARAMETER BundleId
        GUID string identifying this bundle. Stamped into manifest.bundle_id.
    .PARAMETER StartedUtc
        UTC start time of the collection. Drives both collection.started_utc
        and the events_to_utc end of the time window.
    .PARAMETER WindowHours
        Length of the time window in hours. Subtracted from StartedUtc to
        compute events_from_utc. Caller validates the range (1-720).
    .PARAMETER Scenario
        Free-form scenario hint stamped into collection.scenario_hint. One of
        post_patch, performance, general, forensic. Hint only -- does not
        gate which collectors run.
    .PARAMETER CollectorVersion
        Module version string from DiagBundle.psd1. Stamped into
        collection.collector_version.
    .PARAMETER Elevation
        Identity context label (for example SYSTEM, Administrator). Stamped
        into collection.elevation.
    .INPUTS
        None.
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary. The ordered
        hashtable manifest skeleton, ready for collectors to append to.
    .EXAMPLE
        $manifest = Initialize-DiagManifest -BundleId ([guid]::NewGuid()) `
            -StartedUtc ([DateTime]::UtcNow) -WindowHours 24 `
            -Scenario 'post_patch' -CollectorVersion '1.0.0' -Elevation 'SYSTEM'
    .NOTES
        artifacts, collection_errors, redactions_applied, and
        size_budget.truncations are System.Collections.ArrayList instances.
        Callers must use [void]$manifest.artifacts.Add(...) to suppress the
        index return value. Timestamps use ISO-8601 with .fff millisecond
        precision and a Z suffix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $BundleId,
        [Parameter(Mandatory)] [DateTime] $StartedUtc,
        [Parameter(Mandatory)] [int]      $WindowHours,
        [Parameter(Mandatory)] [string]   $Scenario,
        [Parameter(Mandatory)] [string]   $CollectorVersion,
        [Parameter(Mandatory)] [string]   $Elevation
    )

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

    $eventsFrom = $StartedUtc.AddHours(-$WindowHours)

    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    [ordered]@{
        schema_version = '1.3'
        bundle_id      = $BundleId
        host           = [ordered]@{
            computer_name = $env:COMPUTERNAME
            fqdn          = ("{0}.{1}" -f $cs.DNSHostName, $cs.Domain).TrimEnd('.')
            domain        = [string]$cs.Domain
            os_version    = [string]$os.Version
            os_caption    = [string]$os.Caption
            install_date  = $os.InstallDate.ToUniversalTime().ToString($fmt)
            last_boot_utc = $os.LastBootUpTime.ToUniversalTime().ToString($fmt)
        }
        collection     = [ordered]@{
            collector_version  = $CollectorVersion
            started_utc        = $StartedUtc.ToString($fmt)
            completed_utc      = ''
            duration_seconds   = 0
            scenario_hint      = $Scenario
            elevation          = $Elevation
            powershell_version = $PSVersionTable.PSVersion.ToString()
        }
        time_window    = [ordered]@{
            events_from_utc = $eventsFrom.ToString($fmt)
            events_to_utc   = $StartedUtc.ToString($fmt)
            window_hours    = $WindowHours
        }
        artifacts          = [System.Collections.ArrayList]::new()
        collection_errors  = [System.Collections.ArrayList]::new()
        redactions_applied = [System.Collections.ArrayList]::new()
        size_budget        = [ordered]@{
            raw_uncompressed_bytes     = 0
            summary_uncompressed_bytes = 0
            zip_compressed_bytes       = 0
            truncations                = [System.Collections.ArrayList]::new()
        }
    }
}
