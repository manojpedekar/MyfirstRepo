function Get-DiagRegistry {
    <#
    .SYNOPSIS
        Export WindowsUpdate, pending-reboot, and SCCM keys plus an autoruns CSV.

    .DESCRIPTION
        Invoke reg.exe export for five known keys covering WindowsUpdate policy,
        WindowsUpdate client state, CBS RebootPending, Auto Update
        RebootRequired, and the SCCM Reboot Management RebootData blob. Write
        each as a .reg file under raw/registry/. Then enumerate
        Win32_StartupCommand and write raw/registry/autoruns_export.csv. No
        derived summary file is produced. Runs in parallel with peer collectors.
        Reading HKLM and SCCM client keys requires administrator privileges;
        absent keys are normal and recorded as info-level skips.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector writes
        into the existing raw\registry\ subdirectory.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with
        path/category/type/description and per-type metadata), Errors (array of
        hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagRegistry -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - raw/registry/windowsupdate_policies.reg
          - raw/registry/windowsupdate_client_state.reg
          - raw/registry/pending_reboot_cbs.reg
          - raw/registry/pending_reboot_au.reg
          - raw/registry/sccm_reboot_data.reg
          - raw/registry/crashcontrol.reg
          - raw/registry/session_manager_pending_renames.reg
          - raw/registry/autoruns_export.csv

        A missing key produces an info-severity entry in Errors, not a failure;
        a key that exists but cannot be read produces a warning. The autoruns
        CSV failure is also a warning. Never throws; populates Errors and
        returns Success=$false on fatal abort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }

    try {
        $regOut = Join-Path $WorkingDirectory 'raw\registry'

        $exports = @(
            @{ Name = 'windowsupdate_policies.reg';      Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' }
            @{ Name = 'windowsupdate_client_state.reg';  Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' }
            @{ Name = 'pending_reboot_cbs.reg';          Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
            @{ Name = 'pending_reboot_au.reg';           Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
            @{ Name = 'sccm_reboot_data.reg';            Key = 'HKLM\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' }
            @{ Name = 'crashcontrol.reg';                Key = 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' }
            @{ Name = 'session_manager_pending_renames.reg'; Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' }
        )

        foreach ($e in $exports) {
            $out = Join-Path $regOut $e.Name
            try {
                $r = Invoke-DiagTimed -Collector 'Get-DiagRegistry' -Step "reg export $($e.Name)" -Action { & reg.exe export $e.Key $out /y 2>&1 }
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) {
                    $result.Artifacts += @{
                        path        = "raw/registry/$($e.Name)"
                        category    = 'registry_export'
                        type        = 'raw'
                        description = "reg export $($e.Key)"
                    }
                } else {
                    $result.Errors += @{ collector = 'Get-DiagRegistry'; artifact = "raw/registry/$($e.Name)"; reason = "reg export exit ${LASTEXITCODE}: $($r -join '; ')"; severity = 'info' }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRegistry'; artifact = "raw/registry/$($e.Name)"; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        try {
            $autoruns = @(Invoke-DiagTimed -Collector 'Get-DiagRegistry' -Step 'Get-CimInstance Win32_StartupCommand' -Action {
                Get-CimInstance Win32_StartupCommand -ErrorAction Stop
            } | ForEach-Object {
                [ordered]@{
                    Name     = $_.Name
                    Command  = $_.Command
                    Location = $_.Location
                    User     = $_.User
                }
            })
            if ($autoruns.Count -gt 0) {
                $arPath = Join-Path $regOut 'autoruns_export.csv'
                $autoruns | ForEach-Object { New-Object PSObject -Property $_ } |
                    Export-Csv -Path $arPath -NoTypeInformation -Encoding UTF8
                $result.Artifacts += @{
                    path        = 'raw/registry/autoruns_export.csv'
                    category    = 'autoruns'
                    type        = 'raw'
                    description = 'Win32_StartupCommand inventory'
                    row_count   = $autoruns.Count
                }
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRegistry'; artifact = 'raw/registry/autoruns_export.csv'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagRegistry'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
