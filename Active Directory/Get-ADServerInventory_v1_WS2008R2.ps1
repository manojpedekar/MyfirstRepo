<#
.SYNOPSIS
    Exports Windows Server computer objects from one or more AD domains to a timestamped CSV
    using System.DirectoryServices only - no ActiveDirectory module / ADWS required.

.DESCRIPTION
    Backward-compatible companion to Get-ADServerInventory_v1.ps1 for hosts without RSAT or
    where ADWS is unavailable (e.g. Windows Server 2008 R2 / Windows PowerShell 2.0).

    Uses a paged DirectorySearcher against each domain (bound via a serverless LDAP path) to
    retrieve all computer objects whose operatingSystem contains "Server", flags failover-
    cluster virtual objects via the MSClusterVirtualServer SPN, derives Enabled from
    userAccountControl, and writes one combined CSV for all domains. Domains are queried
    sequentially (PowerShell 2.0 has no parallel pipeline).

    IPv4 resolution is best-effort via DNS and only performed with -ResolveIPv4, since a DNS
    lookup per host is slow at scale and not always desired.

.PARAMETER Domain
    One or more AD domain DNS names to query (e.g. "ssnc-corp.global"). Mandatory.

.PARAMETER ExcludeClusters
    Omit failover-cluster virtual computer objects from the output.

.PARAMETER IncludeOU
    Add an 'OU' column containing the object's OU path (outermost-first, '/'-joined).

.PARAMETER ResolveIPv4
    Best-effort DNS resolution of each host's IPv4 address. Slower; off by default.

.PARAMETER OutputPath
    Folder for the CSV and log. Created if missing. Defaults to "C:\temp".

.PARAMETER LogPath
    Optional log-file path. Defaults to a timestamped log under -OutputPath.

.EXAMPLE
    .\Get-ADServerInventory_v1_WS2008R2.ps1 -Domain "ad.dstsystems.com" -IncludeOU

.NOTES
    No module dependencies. Targets Windows PowerShell 2.0+ on Windows Server 2008 R2+.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Domain,

    [switch]$ExcludeClusters,

    [switch]$IncludeOU,

    [switch]$ResolveIPv4,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = 'C:\temp',

    [string]$LogPath
)

#region Helper functions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO',
        [string]$Path
    )
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line  = "$stamp [$Level] $Message"
    switch ($Level) {
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
    if ($Path) {
        try   { Add-Content -Path $Path -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Host "$stamp [WARN] Could not write log '$Path': $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

function Get-DomainServer {
    # Paged DirectorySearcher query for one domain; returns raw PSObjects.
    param([string]$DomainName, [bool]$WantOU, [bool]$WantIPv4)

    $root     = $null
    $searcher = $null
    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainName")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.Filter   = '(&(objectCategory=computer)(operatingSystem=*Server*))'
        $searcher.PageSize = 1000
        [void]$searcher.PropertiesToLoad.AddRange(@(
            'cn', 'dnshostname', 'operatingsystem', 'useraccountcontrol',
            'serviceprincipalname', 'distinguishedname'))

        $found = $searcher.FindAll()
        foreach ($e in $found) {
            $p = $e.Properties

            $uac       = if ($p['useraccountcontrol'].Count -gt 0) { [int]$p['useraccountcontrol'][0] } else { 0 }
            $enabled   = -not ($uac -band 2)
            $dnsName   = if ($p['dnshostname'].Count -gt 0) { [string]$p['dnshostname'][0] } else { $null }
            $spnJoined = if ($p['serviceprincipalname'].Count -gt 0) { ($p['serviceprincipalname'] -join '') } else { '' }
            $isCluster = ($spnJoined -like '*MSClusterVirtualServer*')

            $ou = $null
            if ($WantOU -and $p['distinguishedname'].Count -gt 0) {
                $dn = [string]$p['distinguishedname'][0]
                $ou = (($dn -split ',' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object   { $_ -like 'OU=*' } |
                        ForEach-Object { $_ -replace '^OU=', '' }) -join '/')
            }

            $ipv4 = $null
            if ($WantIPv4 -and $dnsName) {
                try {
                    $ipv4 = ([System.Net.Dns]::GetHostAddresses($dnsName) |
                             Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                             Select-Object -First 1).IPAddressToString
                }
                catch { $ipv4 = $null }
            }

            New-Object PSObject -Property @{
                DomainName      = $DomainName
                Name            = if ($p['cn'].Count -gt 0) { [string]$p['cn'][0] } else { $null }
                DNSHostName     = $dnsName
                IPv4Address     = $ipv4
                OperatingSystem = if ($p['operatingsystem'].Count -gt 0) { [string]$p['operatingsystem'][0] } else { $null }
                Enabled         = $enabled
                IsClusterObject = $isCluster
                OU              = $ou
            }
        }
        $found.Dispose()
    }
    finally {
        if ($searcher) { $searcher.Dispose() }
        if ($root)     { $root.Dispose() }
    }
}
#endregion

#region Prerequisites
try {
    New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    throw "Failed to create output folder '$OutputPath': $($_.Exception.Message)"
}

$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $LogPath) {
    $LogPath = Join-Path -Path $OutputPath -ChildPath "ADServerInventory_WS2008R2_$timestamp.log"
}
$csvPath = Join-Path -Path $OutputPath -ChildPath "ADServerInventory_WS2008R2_$timestamp.csv"
#endregion

#region Main processing
Write-Log -Message "Starting DirectorySearcher inventory across $($Domain.Count) domain(s)." -Path $LogPath

$inventory = New-Object System.Collections.Generic.List[object]
foreach ($d in $Domain) {
    try {
        $servers = @(Get-DomainServer -DomainName $d -WantOU $IncludeOU.IsPresent -WantIPv4 $ResolveIPv4.IsPresent)
        if ($ExcludeClusters) {
            $servers = @($servers | Where-Object { -not $_.IsClusterObject })
        }
        foreach ($s in $servers) { $inventory.Add($s) }
        Write-Log -Message "Queried '$d': $($servers.Count) server object(s) collected." -Path $LogPath
    }
    catch {
        Write-Log -Message "Failed to query '$d': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    }
}
#endregion

#region Summary
if ($inventory.Count -gt 0) {
    $columns = New-Object System.Collections.Generic.List[string]
    'DomainName', 'Name', 'DNSHostName', 'IPv4Address', 'OperatingSystem', 'Enabled' |
        ForEach-Object { $columns.Add($_) }
    if (-not $ExcludeClusters) { $columns.Add('IsClusterObject') }
    if ($IncludeOU)            { $columns.Add('OU') }

    try {
        $inventory | Select-Object $columns | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log -Message "Export complete. $($inventory.Count) object(s) written to '$csvPath'." -Level SUCCESS -Path $LogPath
    }
    catch {
        Write-Log -Message "Failed to write CSV '$csvPath': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    }
}
else {
    Write-Log -Message "No server objects collected. Check domain names, connectivity, and permissions." -Level WARN -Path $LogPath
}

$inventory
#endregion
