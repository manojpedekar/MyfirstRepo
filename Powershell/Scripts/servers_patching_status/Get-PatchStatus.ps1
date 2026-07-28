<#
    .SYNOPSIS
        Reports the last patched date and last reboot date for a list of servers.

    .DESCRIPTION
        Reads server names from servers.txt (one per line, located next to this
        script), then for each reachable server retrieves:
          - Last patched date  : install date of the most recent hotfix
          - Last reboot date    : OS LastBootUpTime
        Results are written to a timestamped CSV in the script folder.

    .PARAMETER ServerListPath
        Path to the text file containing server names. Defaults to servers.txt
        next to the script.

    .EXAMPLE
        .\Get-PatchStatus.ps1
#>

[CmdletBinding()]
Param (
    [string]$ServerListPath = (Join-Path $PSScriptRoot 'servers.txt')
)

If (-not (Test-Path $ServerListPath)) {
    Throw "Server list not found: $ServerListPath. Create it with one server name per line."
}

# Read server names, ignoring blank lines and comments (#)
$Servers = Get-Content $ServerListPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') }

If (-not $Servers) {
    Throw "No server names found in $ServerListPath."
}

$Results = ForEach ($Server In $Servers) {
    Write-Host "Checking $Server ..." -ForegroundColor Cyan

    If (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet)) {
        Write-Warning "$Server is not responding to ping."
        [PSCustomObject]@{
            ComputerName   = $Server
            LastPatchedKB  = $null
            LastPatchedOn  = $null
            LastRebootOn   = $null
            Status         = 'Unreachable'
        }
        Continue
    }

    Try {
        # Last reboot
        $os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Server -ErrorAction Stop
        $LastReboot = $os.ConvertToDateTime($os.LastBootUpTime)

        # Last patch: most recent hotfix by install date
        $LastHotfix = Get-HotFix -ComputerName $Server -ErrorAction Stop |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1

        [PSCustomObject]@{
            ComputerName   = $os.CSName
            LastPatchedKB  = $LastHotfix.HotFixID
            LastPatchedOn  = $LastHotfix.InstalledOn
            LastRebootOn   = $LastReboot
            Status         = 'OK'
        }
    } Catch {
        Write-Warning "Failed to query $($Server): $_"
        [PSCustomObject]@{
            ComputerName   = $Server
            LastPatchedKB  = $null
            LastPatchedOn  = $null
            LastRebootOn   = $null
            Status         = "Error: $($_.Exception.Message)"
        }
    }
}

# Display and export
$Results | Format-Table -AutoSize

$Stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$OutputPath = Join-Path $PSScriptRoot "PatchStatus_$Stamp.csv"
$Results | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host "Results exported to $OutputPath" -ForegroundColor Green
