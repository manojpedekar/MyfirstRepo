<#
.SYNOPSIS
    Collects AD Sites and Services information from the Configuration partition

.DESCRIPTION
    Main orchestrator function for collecting Sites & Services data from Active Directory.
    This function queries the Configuration partition to collect:
    - Sites (AD_Site)
    - Subnets (AD_Subnet)
    - Site Links (AD_SiteLink)
    - Site Settings (AD_SiteSettings)
    - Servers in Sites (AD_SiteServer)
    - Domain Controller NTDS Settings (AD_DomainController)

    Junction tables (AD_SiteSubnet, AD_SiteLinkSite) are populated from the
    multi-valued attributes on the parent objects.

    Sites & Services data is forest-scoped and stored in the Configuration partition,
    which replicates to all DCs in the forest.

.PARAMETER Server
    IP address or hostname of a domain controller to query.

.PARAMETER ForestName
    The forest name (DNS root domain name).

.PARAMETER Config
    ADQueryConfig object with query settings.

.OUTPUTS
    PSCustomObject with the following properties:
    - Sites: Array of site objects
    - Subnets: Array of subnet objects
    - SiteLinks: Array of site link objects
    - SiteSettings: Array of site settings objects
    - SiteServers: Array of server objects
    - DomainControllers: Array of DC NTDS Settings objects
    - SiteSubnets: Array of site-subnet junction records
    - SiteLinkSites: Array of site link-site junction records

.NOTES
    Part of SSNC.ADInventory module

    LDAP LOCATION:
    CN=Sites,CN=Configuration,<ForestDN>

    SCOPE:
    Forest-wide. Sites & Services data is collected once per forest.

    REQUIRED PERMISSIONS:
    Authenticated Users (default read access to Configuration partition)
#>
function Get-ADSitesAndServicesInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ForestName,

        [Parameter(Mandatory = $false)]
        [ADQueryConfig]$Config = [ADQueryConfig]::new()
    )

    process {
        Write-ADInventoryLog -Level Info -Message "Collecting Sites & Services information" `
            -Category Collection `
            -Context @{
                Server = $Server
                ForestName = $ForestName
            }

        try {
            # Get Configuration naming context
            $rootDse = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/RootDSE")
            $configDn = $rootDse.Properties['configurationNamingContext'][0].ToString()
            $rootDse.Dispose()

            $sitesContainer = "CN=Sites,$configDn"

            Write-ADInventoryLog -Level Debug -Message "Configuration partition located" `
                -Context @{
                    ConfigDN = $configDn
                    SitesContainer = $sitesContainer
                }

            # Collect all Sites & Services data
            # NOTE: Wrap all calls in @() to prevent PowerShell from unwrapping single-element arrays
            $sites = @(Get-ADSiteInfoInternal -Server $Server -SitesContainer $sitesContainer -Config $Config)
            $subnets = @(Get-ADSubnetInfoInternal -Server $Server -SitesContainer $sitesContainer -Config $Config)
            $siteLinks = @(Get-ADSiteLinkInfoInternal -Server $Server -ConfigDn $configDn -Config $Config)
            $siteSettings = @(Get-ADSiteSettingsInfoInternal -Server $Server -SitesContainer $sitesContainer -Config $Config)
            $siteServers = @(Get-ADSiteServerInfoInternal -Server $Server -SitesContainer $sitesContainer -Config $Config)
            $domainControllers = @(Get-ADDomainControllerInfoInternal -Server $Server -SitesContainer $sitesContainer -Config $Config)

            # Build junction tables from multi-valued attributes
            $siteSubnets = @(Build-SiteSubnetJunction -Subnets $subnets)
            $siteLinkSites = @(Build-SiteLinkSiteJunction -SiteLinks $siteLinks)

            $result = [PSCustomObject]@{
                Sites            = $sites
                Subnets          = $subnets
                SiteLinks        = $siteLinks
                SiteSettings     = $siteSettings
                SiteServers      = $siteServers
                DomainControllers = $domainControllers
                SiteSubnets      = $siteSubnets
                SiteLinkSites    = $siteLinkSites
            }

            Write-ADInventoryLog -Level Info -Message "Sites & Services collection completed" `
                -Category Collection `
                -Context @{
                    SiteCount = $sites.Count
                    SubnetCount = $subnets.Count
                    SiteLinkCount = $siteLinks.Count
                    SiteSettingsCount = $siteSettings.Count
                    SiteServerCount = $siteServers.Count
                    DCCount = $domainControllers.Count
                    SiteSubnetJunctions = $siteSubnets.Count
                    SiteLinkSiteJunctions = $siteLinkSites.Count
                }

            return $result
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to collect Sites & Services information" `
                -Category Collection `
                -Context @{ Server = $Server; ForestName = $ForestName } `
                -Exception $_.Exception
            throw
        }
    }
}

#region Internal Helper Functions

function Get-ADSiteInfoInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SitesContainer,
        [ADQueryConfig]$Config
    )

    $sites = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$SitesContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=site)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'description', 'location', 'distinguishedName',
            'objectGUID', 'whenCreated', 'whenChanged'
        )
        $searcher.PropertiesToLoad.AddRange($propertiesToLoad)

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $objectGuid = $null
            if ($props['objectguid'] -and $props['objectguid'].Count -gt 0) {
                $guidBytes = $props['objectguid'][0]
                if ($guidBytes -is [byte[]]) {
                    $objectGuid = ([guid]$guidBytes).ToString()
                }
            }

            $site = [PSCustomObject]@{
                SiteName          = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                Description       = if ($props['description'] -and $props['description'].Count -gt 0) { [string]$props['description'][0] } else { $null }
                Location          = if ($props['location'] -and $props['location'].Count -gt 0) { [string]$props['location'][0] } else { $null }
                DistinguishedName = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID        = $objectGuid
                WhenCreated       = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged       = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }
            [void]$sites.Add($site)
        }

        Write-ADInventoryLog -Level Debug -Message "Sites query completed" `
            -Context @{ Server = $Server; SiteCount = $sites.Count }

        return $sites.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query sites" `
            -Context @{ Server = $Server; SitesContainer = $SitesContainer } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Get-ADSubnetInfoInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SitesContainer,
        [ADQueryConfig]$Config
    )

    $subnets = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $subnetsContainer = "CN=Subnets,$SitesContainer"
        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$subnetsContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=subnet)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'description', 'location', 'siteObject',
            'distinguishedName', 'objectGUID', 'whenCreated', 'whenChanged'
        )
        $searcher.PropertiesToLoad.AddRange($propertiesToLoad)

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $objectGuid = $null
            if ($props['objectguid'] -and $props['objectguid'].Count -gt 0) {
                $guidBytes = $props['objectguid'][0]
                if ($guidBytes -is [byte[]]) {
                    $objectGuid = ([guid]$guidBytes).ToString()
                }
            }

            # Extract site name from siteObject DN
            $siteObjectDn = if ($props['siteobject'] -and $props['siteobject'].Count -gt 0) { [string]$props['siteobject'][0] } else { $null }
            $siteName = $null
            if ($siteObjectDn -match '^CN=([^,]+),') {
                $siteName = $Matches[1]
            }

            $subnet = [PSCustomObject]@{
                SubnetName        = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                Description       = if ($props['description'] -and $props['description'].Count -gt 0) { [string]$props['description'][0] } else { $null }
                Location          = if ($props['location'] -and $props['location'].Count -gt 0) { [string]$props['location'][0] } else { $null }
                SiteName          = $siteName
                SiteObjectDN      = $siteObjectDn
                DistinguishedName = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID        = $objectGuid
                WhenCreated       = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged       = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }
            [void]$subnets.Add($subnet)
        }

        Write-ADInventoryLog -Level Debug -Message "Subnets query completed" `
            -Context @{ Server = $Server; SubnetCount = $subnets.Count }

        return $subnets.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query subnets" `
            -Context @{ Server = $Server; SitesContainer = $SitesContainer } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Get-ADSiteLinkInfoInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$ConfigDn,
        [ADQueryConfig]$Config
    )

    $siteLinks = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        # Query IP transport site links (most common)
        $transportContainer = "CN=IP,CN=Inter-Site Transports,CN=Sites,$ConfigDn"
        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$transportContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=siteLink)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'cost', 'replInterval', 'options', 'siteList',
            'schedule', 'description', 'distinguishedName',
            'objectGUID', 'whenCreated', 'whenChanged'
        )
        $searcher.PropertiesToLoad.AddRange($propertiesToLoad)

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $objectGuid = $null
            if ($props['objectguid'] -and $props['objectguid'].Count -gt 0) {
                $guidBytes = $props['objectguid'][0]
                if ($guidBytes -is [byte[]]) {
                    $objectGuid = ([guid]$guidBytes).ToString()
                }
            }

            # Extract site names from siteList DNs
            $siteList = @()
            $siteListDNs = @()
            if ($props['sitelist'] -and $props['sitelist'].Count -gt 0) {
                foreach ($siteDn in $props['sitelist']) {
                    $siteDnString = [string]$siteDn
                    $siteListDNs += $siteDnString
                    if ($siteDnString -match '^CN=([^,]+),') {
                        $siteList += $Matches[1]
                    }
                }
            }

            # Extract options flags
            $options = 0
            if ($props['options'] -and $props['options'].Count -gt 0) {
                $options = [int]$props['options'][0]
            }
            $useNotification = ($options -band 1) -eq 1
            $twoWaySync = ($options -band 2) -eq 2
            $compressionDisabled = ($options -band 4) -eq 4

            # Extract schedule as Base64
            $schedule = $null
            if ($props['schedule'] -and $props['schedule'].Count -gt 0) {
                $scheduleBytes = $props['schedule'][0]
                if ($scheduleBytes -is [byte[]]) {
                    $schedule = [Convert]::ToBase64String($scheduleBytes)
                }
            }

            # Cost defaults to 100, replInterval defaults to 180
            $cost = 100
            if ($props['cost'] -and $props['cost'].Count -gt 0) {
                $cost = [int]$props['cost'][0]
            }
            $replInterval = 180
            if ($props['replinterval'] -and $props['replinterval'].Count -gt 0) {
                $replInterval = [int]$props['replinterval'][0]
            }

            $siteLink = [PSCustomObject]@{
                SiteLinkName        = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                Cost                = $cost
                ReplicationInterval = $replInterval
                Options             = $options
                UseNotification     = $useNotification
                TwoWaySync          = $twoWaySync
                CompressionDisabled = $compressionDisabled
                SiteCount           = $siteList.Count
                SiteList            = ($siteList | ConvertTo-Json -Compress)
                SiteListDNs         = $siteListDNs  # For junction table
                Schedule            = $schedule
                Description         = if ($props['description'] -and $props['description'].Count -gt 0) { [string]$props['description'][0] } else { $null }
                TransportType       = 'IP'
                DistinguishedName   = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID          = $objectGuid
                WhenCreated         = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged         = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }
            [void]$siteLinks.Add($siteLink)
        }

        Write-ADInventoryLog -Level Debug -Message "SiteLinks query completed" `
            -Context @{ Server = $Server; SiteLinkCount = $siteLinks.Count }

        return $siteLinks.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query site links" `
            -Context @{ Server = $Server; ConfigDn = $ConfigDn } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Get-ADSiteSettingsInfoInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SitesContainer,
        [ADQueryConfig]$Config
    )

    $siteSettings = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$SitesContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=nTDSSiteSettings)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'interSiteTopologyGenerator', 'options', 'schedule',
            'distinguishedName', 'objectGUID', 'whenCreated', 'whenChanged'
        )
        $searcher.PropertiesToLoad.AddRange($propertiesToLoad)

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $dn = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }

            # Extract site name from DN
            $siteName = $null
            if ($dn -match 'CN=NTDS Site Settings,CN=([^,]+),CN=Sites,') {
                $siteName = $Matches[1]
            }

            $objectGuid = $null
            if ($props['objectguid'] -and $props['objectguid'].Count -gt 0) {
                $guidBytes = $props['objectguid'][0]
                if ($guidBytes -is [byte[]]) {
                    $objectGuid = ([guid]$guidBytes).ToString()
                }
            }

            # Extract ISTG
            $istg = $null
            $istgName = $null
            if ($props['intersitetopologygenerator'] -and $props['intersitetopologygenerator'].Count -gt 0) {
                $istg = [string]$props['intersitetopologygenerator'][0]
                if ($istg -match 'CN=NTDS Settings,CN=([^,]+),') {
                    $istgName = $Matches[1]
                }
            }

            # Extract options
            $options = 0
            if ($props['options'] -and $props['options'].Count -gt 0) {
                $options = [int]$props['options'][0]
            }

            # Decode options bitmask
            $isAutoTopologyDisabled = ($options -band 1) -eq 1
            $isTopologyCleanupDisabled = ($options -band 2) -eq 2
            $isMinHopsDisabled = ($options -band 4) -eq 4
            $isDetectStaleDisabled = ($options -band 8) -eq 8
            $isInterSiteAutoTopologyDisabled = ($options -band 16) -eq 16
            $isGroupCachingEnabled = ($options -band 32) -eq 32

            # Extract schedule as Base64
            $schedule = $null
            if ($props['schedule'] -and $props['schedule'].Count -gt 0) {
                $scheduleBytes = $props['schedule'][0]
                if ($scheduleBytes -is [byte[]]) {
                    $schedule = [Convert]::ToBase64String($scheduleBytes)
                }
            }

            $setting = [PSCustomObject]@{
                SiteName                        = $siteName
                InterSiteTopologyGenerator      = $istg
                InterSiteTopologyGeneratorName  = $istgName
                Options                         = $options
                IsAutoTopologyDisabled          = $isAutoTopologyDisabled
                IsTopologyCleanupDisabled       = $isTopologyCleanupDisabled
                IsMinHopsDisabled               = $isMinHopsDisabled
                IsDetectStaleDisabled           = $isDetectStaleDisabled
                IsInterSiteAutoTopologyDisabled = $isInterSiteAutoTopologyDisabled
                IsGroupCachingEnabled           = $isGroupCachingEnabled
                Schedule                        = $schedule
                DistinguishedName               = $dn
                ObjectGUID                      = $objectGuid
                WhenCreated                     = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged                     = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }
            [void]$siteSettings.Add($setting)
        }

        Write-ADInventoryLog -Level Debug -Message "SiteSettings query completed" `
            -Context @{ Server = $Server; SiteSettingsCount = $siteSettings.Count }

        return $siteSettings.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query site settings" `
            -Context @{ Server = $Server; SitesContainer = $SitesContainer } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Get-ADSiteServerInfoInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SitesContainer,
        [ADQueryConfig]$Config
    )

    $servers = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$SitesContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=server)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'dNSHostName', 'serverReference',
            'distinguishedName', 'objectGUID', 'whenCreated', 'whenChanged'
        )
        $searcher.PropertiesToLoad.AddRange($propertiesToLoad)

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $dn = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }

            # Extract site name from DN: CN=ServerName,CN=Servers,CN=SiteName,CN=Sites,...
            $siteName = $null
            if ($dn -match 'CN=Servers,CN=([^,]+),CN=Sites,') {
                $siteName = $Matches[1]
            }

            $objectGuid = $null
            if ($props['objectguid'] -and $props['objectguid'].Count -gt 0) {
                $guidBytes = $props['objectguid'][0]
                if ($guidBytes -is [byte[]]) {
                    $objectGuid = ([guid]$guidBytes).ToString()
                }
            }

            # serverReference points to the computer object in AD
            $serverRef = if ($props['serverreference'] -and $props['serverreference'].Count -gt 0) { [string]$props['serverreference'][0] } else { $null }

            $srv = [PSCustomObject]@{
                ServerName        = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                SiteName          = $siteName
                DNSHostName       = if ($props['dnshostname'] -and $props['dnshostname'].Count -gt 0) { [string]$props['dnshostname'][0] } else { $null }
                ServerReference   = $serverRef
                DistinguishedName = $dn
                ObjectGUID        = $objectGuid
                WhenCreated       = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged       = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }
            [void]$servers.Add($srv)
        }

        Write-ADInventoryLog -Level Debug -Message "SiteServers query completed" `
            -Context @{ Server = $Server; SiteServerCount = $servers.Count }

        return $servers.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query site servers" `
            -Context @{ Server = $Server; SitesContainer = $SitesContainer } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Get-ADDomainControllerInfoInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SitesContainer,
        [ADQueryConfig]$Config
    )

    $dcs = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$SitesContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=nTDSDSA)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'options', 'invocationId', 'msDS-HasDomainNCs', 'msDS-hasMasterNCs',
            'msDS-HasInstantiatedNCs', 'hasMasterNCs',
            'distinguishedName', 'objectGUID', 'whenCreated', 'whenChanged'
        )
        $searcher.PropertiesToLoad.AddRange($propertiesToLoad)

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $dn = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }

            # Extract server name and site name from DN
            # DN format: CN=NTDS Settings,CN=ServerName,CN=Servers,CN=SiteName,CN=Sites,...
            $serverName = $null
            $siteName = $null
            if ($dn -match 'CN=NTDS Settings,CN=([^,]+),CN=Servers,CN=([^,]+),CN=Sites,') {
                $serverName = $Matches[1]
                $siteName = $Matches[2]
            }

            $objectGuid = $null
            if ($props['objectguid'] -and $props['objectguid'].Count -gt 0) {
                $guidBytes = $props['objectguid'][0]
                if ($guidBytes -is [byte[]]) {
                    $objectGuid = ([guid]$guidBytes).ToString()
                }
            }

            # Extract invocationId
            $invocationId = $null
            if ($props['invocationid'] -and $props['invocationid'].Count -gt 0) {
                $guidBytes = $props['invocationid'][0]
                if ($guidBytes -is [byte[]]) {
                    $invocationId = ([guid]$guidBytes).ToString()
                }
            }

            # Extract options
            $options = 0
            if ($props['options'] -and $props['options'].Count -gt 0) {
                $options = [int]$props['options'][0]
            }

            # Decode NTDSDSA options bitmask
            $isGlobalCatalog = ($options -band 1) -eq 1
            $disableInboundReplication = ($options -band 2) -eq 2
            $disableOutboundReplication = ($options -band 4) -eq 4
            $disableNTDSConnTranslation = ($options -band 8) -eq 8
            $isRODC = ($options -band 32) -eq 32

            # Get naming contexts (as JSON array)
            $masterNCs = @()
            if ($props['hasmasterncs'] -and $props['hasmasterncs'].Count -gt 0) {
                $masterNCs = @($props['hasmasterncs'])
            }
            elseif ($props['msds-hasmasterncs'] -and $props['msds-hasmasterncs'].Count -gt 0) {
                $masterNCs = @($props['msds-hasmasterncs'])
            }

            $dc = [PSCustomObject]@{
                ServerName                   = $serverName
                SiteName                     = $siteName
                Options                      = $options
                IsGlobalCatalog              = $isGlobalCatalog
                DisableInboundReplication    = $disableInboundReplication
                DisableOutboundReplication   = $disableOutboundReplication
                DisableNTDSConnTranslation   = $disableNTDSConnTranslation
                IsRODC                       = $isRODC
                InvocationId                 = $invocationId
                MasterNCs                    = ($masterNCs | ConvertTo-Json -Compress)
                DistinguishedName            = $dn
                ObjectGUID                   = $objectGuid
                WhenCreated                  = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged                  = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }
            [void]$dcs.Add($dc)
        }

        Write-ADInventoryLog -Level Debug -Message "DomainControllers query completed" `
            -Context @{ Server = $Server; DCCount = $dcs.Count }

        return $dcs.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query domain controllers" `
            -Context @{ Server = $Server; SitesContainer = $SitesContainer } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Build-SiteSubnetJunction {
    [CmdletBinding()]
    param(
        [array]$Subnets
    )

    $junctions = [System.Collections.ArrayList]::new()

    if ($Subnets -and $Subnets.Count -gt 0) {
        foreach ($subnet in $Subnets) {
            if (-not [string]::IsNullOrEmpty($subnet.SiteName)) {
                $junction = [PSCustomObject]@{
                    SiteName   = $subnet.SiteName
                    SubnetName = $subnet.SubnetName
                }
                [void]$junctions.Add($junction)
            }
        }
    }

    return $junctions.ToArray()
}

function Build-SiteLinkSiteJunction {
    [CmdletBinding()]
    param(
        [array]$SiteLinks
    )

    $junctions = [System.Collections.ArrayList]::new()

    if ($SiteLinks -and $SiteLinks.Count -gt 0) {
        foreach ($siteLink in $SiteLinks) {
            if ($siteLink.SiteListDNs -and $siteLink.SiteListDNs.Count -gt 0) {
                foreach ($siteDn in $siteLink.SiteListDNs) {
                    # Extract site name from DN
                    $siteName = $null
                    if ($siteDn -match '^CN=([^,]+),') {
                        $siteName = $Matches[1]
                    }

                    if ($siteName) {
                        $junction = [PSCustomObject]@{
                            SiteLinkName = $siteLink.SiteLinkName
                            SiteName     = $siteName
                        }
                        [void]$junctions.Add($junction)
                    }
                }
            }
        }
    }

    return $junctions.ToArray()
}

#endregion
