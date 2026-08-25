<#
.SYNOPSIS
    Exports Windows Server computer objects from one or more Active Directory domains to a
    single timestamped CSV, optionally excluding failover-cluster virtual objects.

.DESCRIPTION
    Consolidates four legacy single-purpose export scripts into one parameterized tool:

        Export_AD_Data_With_ADWS.ps1                         (single domain, OU + cluster flag)
        Export_Mutliple_AD_Data_With_ADWS.ps1                (multi-domain, cluster flag)
        Export_Multiple_AD_Data_Exclude_Cluster_With_ADWS.ps1(multi-domain, clusters excluded)

    For each domain it queries all computer objects whose operatingSystem contains "Server",
    flags failover-cluster virtual computer objects (identified by the MSClusterVirtualServer
    SPN), optionally derives the OU path, and writes one combined CSV for all domains.

    Requires the ActiveDirectory module (RSAT / ADWS). For environments without ADWS or RSAT,
    use the DirectorySearcher-based companion: Get-ADServerInventory_v1_WS2008R2.ps1.

    On PowerShell 7+, domains are queried in parallel (configurable throttle). On Windows
    PowerShell 5.1 the same work runs sequentially.

.PARAMETER Domain
    One or more AD domains (or specific domain controllers) to query. Mandatory.

.PARAMETER ExcludeClusters
    Omit failover-cluster virtual computer objects from the output.

.PARAMETER IncludeOU
    Add an 'OU' column containing the object's OU path (outermost-first, '/'-joined).

.PARAMETER OutputPath
    Folder for the CSV and log. Created if missing. Defaults to "C:\temp".

.PARAMETER ThrottleLimit
    Maximum domains queried concurrently on PowerShell 7+. Ignored on 5.1. Defaults to 8.

.PARAMETER LogPath
    Optional log-file path. Defaults to a timestamped log under -OutputPath.

.EXAMPLE
    .\Get-ADServerInventory_v1.ps1 -Domain "ssnc-corp.global" -IncludeOU

.EXAMPLE
    .\Get-ADServerInventory_v1.ps1 -Domain "ad.dstsystems.com","sscdirect.com" -ExcludeClusters

.NOTES
    Returns the inventory objects to the pipeline; the CSV/log are side effects.
    Requires the ActiveDirectory PowerShell module.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Domain,

    [switch]$ExcludeClusters,

    [switch]$IncludeOU,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = 'C:\temp',

    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 8,

    [string]$LogPath
)

#region Helper functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO',
        [string]$Path
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line      = "$timestamp [$Level] $Message"
    switch ($Level) {
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
    if ($Path) {
        try   { Add-Content -Path $Path -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Host "$timestamp [WARN] Could not write log '$Path': $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
#endregion

#region Prerequisites
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw "The ActiveDirectory module is not installed. Install RSAT: Active Directory tools, or use Get-ADServerInventory_v1_WS2008R2.ps1 (no ADWS required)."
}
Import-Module ActiveDirectory -ErrorAction Stop

try {
    New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    throw "Failed to create output folder '$OutputPath': $($_.Exception.Message)"
}

$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $LogPath) {
    $LogPath = Join-Path -Path $OutputPath -ChildPath "ADServerInventory_$timestamp.log"
}
$csvPath = Join-Path -Path $OutputPath -ChildPath "ADServerInventory_$timestamp.csv"

# Properties requested from AD and the LDAP filter are shared by both execution paths.
$adProperties = @('OperatingSystem', 'DNSHostName', 'IPv4Address', 'servicePrincipalName', 'DistinguishedName')
$ldapFilter   = '(operatingSystem=*Server*)'
#endregion

#region Main processing
Write-Log -Message "Starting server inventory across $($Domain.Count) domain(s). ExcludeClusters=$($ExcludeClusters.IsPresent) IncludeOU=$($IncludeOU.IsPresent)." -Path $LogPath

# Query one domain and return a status object. Defined as a scriptblock so the identical
# logic runs both in a PS7 parallel runspace and in the 5.1 sequential loop.
$queryDomain = {
    param($DomainName, $Props, $Filter, $WantOU)

    $result = [PSCustomObject]@{
        Domain  = $DomainName
        Servers = @()
        Error   = $null
    }
    try {
        $computers = Get-ADComputer -Server $DomainName -LDAPFilter $Filter -Properties $Props -ErrorAction Stop

        $result.Servers = foreach ($c in $computers) {
            $isCluster = $false
            if ($c.servicePrincipalName -and (($c.servicePrincipalName -join '') -like '*MSClusterVirtualServer*')) {
                $isCluster = $true
            }

            $ou = $null
            if ($WantOU -and $c.DistinguishedName) {
                $ou = (($c.DistinguishedName -split ',' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object   { $_ -like 'OU=*' } |
                        ForEach-Object { $_ -replace '^OU=', '' }) -join '/')
            }

            [PSCustomObject]@{
                DomainName      = $DomainName
                Name            = $c.Name
                DNSHostName     = $c.DNSHostName
                IPv4Address     = $c.IPv4Address
                OperatingSystem = $c.OperatingSystem
                Enabled         = $c.Enabled
                IsClusterObject = $isCluster
                OU              = $ou
            }
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    $result
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Log -Message "PowerShell 7+ detected; querying domains in parallel (throttle $ThrottleLimit)." -Path $LogPath
    $domainResults = $Domain | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $sb = [scriptblock]::Create($using:queryDomain)
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        & $sb $_ $using:adProperties $using:ldapFilter $using:IncludeOU.IsPresent
    }
}
else {
    Write-Log -Message "Windows PowerShell $($PSVersionTable.PSVersion) detected; querying domains sequentially." -Path $LogPath
    $domainResults = foreach ($d in $Domain) {
        & $queryDomain $d $adProperties $ldapFilter $IncludeOU.IsPresent
    }
}

# Aggregate on the main thread (log here so console output is not interleaved by parallelism).
$inventory = [System.Collections.Generic.List[object]]::new()
foreach ($dr in $domainResults) {
    if ($dr.Error) {
        Write-Log -Message "Failed to query '$($dr.Domain)': $($dr.Error)" -Level ERROR -Path $LogPath
        continue
    }
    $servers = @($dr.Servers)
    if ($ExcludeClusters) {
        $servers = @($servers | Where-Object { -not $_.IsClusterObject })
    }
    foreach ($s in $servers) { $inventory.Add($s) }
    Write-Log -Message "Queried '$($dr.Domain)': $($servers.Count) server object(s) collected." -Path $LogPath
}
#endregion

#region Summary
if ($inventory.Count -gt 0) {
    # Drop the helper cluster flag from the CSV when the caller filtered on it; keep the OU
    # column only when requested so the file matches the caller's intent.
    $columns = [System.Collections.Generic.List[string]]@('DomainName', 'Name', 'DNSHostName', 'IPv4Address', 'OperatingSystem', 'Enabled')
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

# Emit objects to the pipeline (formatting/CSV above are side effects).
$inventory
#endregion
