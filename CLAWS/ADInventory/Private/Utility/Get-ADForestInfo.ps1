function Get-ADForestInfo {
    <#
    .SYNOPSIS
        Retrieves comprehensive forest information including FSMO roles

    .DESCRIPTION
        Queries Active Directory to collect forest-level information including:
        - Forest identity (name, root domain)
        - Functional level
        - FSMO role holders (Schema Master, Domain Naming Master)
        - All domains in the forest
        - Global Catalog servers
        - Sites and site links
        - Schema version information

    .PARAMETER ForestName
        The forest name to get information for (typically the root domain DNS name)

    .PARAMETER Server
        Optional domain controller to query. If not specified, uses forest name.

    .OUTPUTS
        PSCustomObject with forest properties

    .EXAMPLE
        $forestInfo = Get-ADForestInfo -ForestName "contoso.com"

    .NOTES
        Part of SSNC.ADInventory module

        Forest Functional Levels (msDS-Behavior-Version on Partitions container):
        0 = Windows 2000
        1 = Windows Server 2003 Interim
        2 = Windows Server 2003
        3 = Windows Server 2008
        4 = Windows Server 2008 R2
        5 = Windows Server 2012
        6 = Windows Server 2012 R2
        7 = Windows Server 2016

        Schema Versions:
        13 = Windows 2000
        30 = Windows Server 2003
        31 = Windows Server 2003 R2
        44 = Windows Server 2008
        47 = Windows Server 2008 R2
        56 = Windows Server 2012
        69 = Windows Server 2012 R2
        87 = Windows Server 2016
        88 = Windows Server 2019
        90 = Windows Server 2022
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ForestName,

        [Parameter(Mandatory = $false)]
        [string]$Server
    )

    process {
        Write-ADInventoryLog -Level Info -Message "Retrieving forest information" `
            -Context @{ ForestName = $ForestName }

        try {
            $ldapServer = if ($Server) { $Server } else { $ForestName }

            # Get RootDSE for naming contexts
            $rootDSE = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$ldapServer/RootDSE")
            $configNC = $rootDSE.Properties['configurationNamingContext'][0].ToString()
            $schemaNC = $rootDSE.Properties['schemaNamingContext'][0].ToString()
            $rootDomainNC = $rootDSE.Properties['rootDomainNamingContext'][0].ToString()
            $rootDSE.Dispose()

            # Convert root domain DN to DNS name
            $rootDomain = ($rootDomainNC -replace 'DC=', '' -replace ',', '.').TrimStart('.')

            Write-ADInventoryLog -Level Debug -Message "Querying forest configuration" `
                -Context @{ ConfigNC = $configNC; Server = $ldapServer }

            # Get forest functional level from Partitions container
            $partitionsPath = "LDAP://$ldapServer/CN=Partitions,$configNC"
            $partitionsEntry = [System.DirectoryServices.DirectoryEntry]::new($partitionsPath)
            $partitionsEntry.RefreshCache(@('msDS-Behavior-Version', 'objectGUID', 'fSMORoleOwner'))

            $forestModeLevel = if ($partitionsEntry.Properties['msDS-Behavior-Version'].Count -gt 0) {
                [int]$partitionsEntry.Properties['msDS-Behavior-Version'][0]
            } else { -1 }

            $forestMode = Get-FunctionalLevelName -Level $forestModeLevel -Type 'Forest'

            # Get forest GUID
            $forestGUID = $null
            if ($partitionsEntry.Properties['objectGUID'].Count -gt 0) {
                $guidBytes = $partitionsEntry.Properties['objectGUID'][0]
                $forestGUID = ([guid]$guidBytes).ToString()
            }

            # Get Domain Naming Master
            $domainNamingMaster = $null
            if ($partitionsEntry.Properties['fSMORoleOwner'].Count -gt 0) {
                $domainNamingMaster = Extract-ServerFromNTDSDSA $partitionsEntry.Properties['fSMORoleOwner'][0].ToString()
            }

            $partitionsEntry.Dispose()

            # Get whenCreated from Configuration partition (forest creation date)
            # The Configuration partition is created when the forest is established
            $whenCreated = $null
            try {
                $configPath = "LDAP://$ldapServer/$configNC"
                $configEntry = [System.DirectoryServices.DirectoryEntry]::new($configPath)
                $configEntry.RefreshCache(@('whenCreated'))

                if ($configEntry.Properties['whenCreated'].Count -gt 0) {
                    $whenCreated = [DateTime]$configEntry.Properties['whenCreated'][0]
                }

                $configEntry.Dispose()
            }
            catch {
                Write-ADInventoryLog -Level Debug -Message "Failed to get Configuration partition whenCreated" `
                    -Exception $_.Exception
            }

            # Get Schema Master from Schema container
            $schemaPath = "LDAP://$ldapServer/$schemaNC"
            $schemaEntry = [System.DirectoryServices.DirectoryEntry]::new($schemaPath)
            $schemaEntry.RefreshCache(@('fSMORoleOwner', 'objectVersion'))

            $schemaMaster = $null
            if ($schemaEntry.Properties['fSMORoleOwner'].Count -gt 0) {
                $schemaMaster = Extract-ServerFromNTDSDSA $schemaEntry.Properties['fSMORoleOwner'][0].ToString()
            }

            $schemaVersion = if ($schemaEntry.Properties['objectVersion'].Count -gt 0) {
                [int]$schemaEntry.Properties['objectVersion'][0]
            } else { $null }

            $schemaEntry.Dispose()

            # Get Exchange schema version (if present)
            $exchangeSchemaVersion = Get-ExchangeSchemaVersion -SchemaNC $schemaNC -Server $ldapServer

            # Get all domains in forest
            $domains = Get-ForestDomainList -ConfigNC $configNC -Server $ldapServer

            # Get Global Catalog servers
            $globalCatalogs = Get-GlobalCatalogServers -ConfigNC $configNC -Server $ldapServer

            # Get sites
            $sites = Get-ADSiteList -ConfigNC $configNC -Server $ldapServer

            # Get site links
            $siteLinks = Get-ADSiteLinkList -ConfigNC $configNC -Server $ldapServer

            $result = [PSCustomObject]@{
                ForestName            = $ForestName
                ForestGUID            = $forestGUID
                RootDomain            = $rootDomain
                ForestMode            = $forestMode
                ForestModeLevel       = $forestModeLevel
                SchemaMaster          = $schemaMaster
                DomainNamingMaster    = $domainNamingMaster
                Domains               = if ($domains.Count -gt 0) { $domains | ConvertTo-Json -Compress } else { $null }
                GlobalCatalogs        = if ($globalCatalogs.Count -gt 0) { $globalCatalogs | ConvertTo-Json -Compress } else { $null }
                Sites                 = if ($sites.Count -gt 0) { $sites | ConvertTo-Json -Compress } else { $null }
                SiteLinks             = if ($siteLinks.Count -gt 0) { $siteLinks | ConvertTo-Json -Compress } else { $null }
                SchemaVersion         = $schemaVersion
                ExchangeSchemaVersion = $exchangeSchemaVersion
                WhenCreated           = $whenCreated
            }

            Write-ADInventoryLog -Level Info -Message "Forest information retrieved" `
                -Context @{
                    ForestName = $ForestName
                    ForestMode = $forestMode
                    DomainCount = $domains.Count
                    GCCount = $globalCatalogs.Count
                    SiteCount = $sites.Count
                }

            return $result
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to get forest information" `
                -Context @{ ForestName = $ForestName } `
                -Exception $_.Exception
            throw "Failed to get forest information for $ForestName : $_"
        }
    }
}

function Get-ExchangeSchemaVersion {
    <#
    .SYNOPSIS
        Gets the Exchange schema version if present
    #>
    [CmdletBinding()]
    param(
        [string]$SchemaNC,
        [string]$Server
    )

    try {
        # Exchange schema version is stored in rangeUpper attribute of ms-Exch-Schema-Version-Pt
        $exchSchemaPath = "LDAP://$Server/CN=ms-Exch-Schema-Version-Pt,$SchemaNC"
        $exchSchemaEntry = [System.DirectoryServices.DirectoryEntry]::new($exchSchemaPath)
        $exchSchemaEntry.RefreshCache(@('rangeUpper'))

        $version = if ($exchSchemaEntry.Properties['rangeUpper'].Count -gt 0) {
            [int]$exchSchemaEntry.Properties['rangeUpper'][0]
        } else { $null }

        $exchSchemaEntry.Dispose()
        return $version
    }
    catch {
        # Exchange schema not present - this is normal for non-Exchange environments
        return $null
    }
}

function Get-ForestDomainList {
    <#
    .SYNOPSIS
        Gets all domains in the forest
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigNC,
        [string]$Server
    )

    $domains = @()

    try {
        $partitionsPath = "LDAP://$Server/CN=Partitions,$ConfigNC"
        $partitionsEntry = [System.DirectoryServices.DirectoryEntry]::new($partitionsPath)
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($partitionsEntry)
        # Filter for domain NCs (systemFlags contains 3 = NC + DOMAIN)
        $searcher.Filter = "(&(objectClass=crossRef)(systemFlags:1.2.840.113556.1.4.803:=3))"
        $searcher.PropertiesToLoad.Add('dnsRoot') | Out-Null
        $searcher.PageSize = 100

        $results = $searcher.FindAll()

        foreach ($result in $results) {
            if ($result.Properties['dnsroot'].Count -gt 0) {
                $domains += $result.Properties['dnsroot'][0].ToString()
            }
        }

        $results.Dispose()
        $searcher.Dispose()
        $partitionsEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to enumerate forest domains" `
            -Exception $_.Exception
    }

    return $domains
}

function Get-GlobalCatalogServers {
    <#
    .SYNOPSIS
        Gets all Global Catalog servers in the forest
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigNC,
        [string]$Server
    )

    $gcServers = @()

    try {
        $sitesPath = "LDAP://$Server/CN=Sites,$ConfigNC"
        $sitesEntry = [System.DirectoryServices.DirectoryEntry]::new($sitesPath)
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($sitesEntry)
        # Search for NTDS Settings objects where options has GC bit (1)
        $searcher.Filter = "(&(objectClass=nTDSDSA)(options:1.2.840.113556.1.4.803:=1))"
        $searcher.PropertiesToLoad.Add('distinguishedName') | Out-Null
        $searcher.PageSize = 1000

        $results = $searcher.FindAll()

        foreach ($result in $results) {
            $ntdsDN = $result.Properties['distinguishedname'][0].ToString()
            $serverName = Extract-ServerFromNTDSDSA $ntdsDN
            if ($serverName) {
                $gcServers += $serverName
            }
        }

        $results.Dispose()
        $searcher.Dispose()
        $sitesEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to enumerate Global Catalogs" `
            -Exception $_.Exception
    }

    return $gcServers
}

function Get-ADSiteList {
    <#
    .SYNOPSIS
        Gets all AD sites in the forest
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigNC,
        [string]$Server
    )

    $sites = @()

    try {
        $sitesPath = "LDAP://$Server/CN=Sites,$ConfigNC"
        $sitesEntry = [System.DirectoryServices.DirectoryEntry]::new($sitesPath)
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($sitesEntry)
        $searcher.Filter = "(objectClass=site)"
        $searcher.PropertiesToLoad.Add('name') | Out-Null
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = 1000

        $results = $searcher.FindAll()

        foreach ($result in $results) {
            if ($result.Properties['name'].Count -gt 0) {
                $sites += $result.Properties['name'][0].ToString()
            }
        }

        $results.Dispose()
        $searcher.Dispose()
        $sitesEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to enumerate sites" `
            -Exception $_.Exception
    }

    return $sites
}

function Get-ADSiteLinkList {
    <#
    .SYNOPSIS
        Gets all AD site links in the forest
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigNC,
        [string]$Server
    )

    $siteLinks = @()

    try {
        $ipTransportPath = "LDAP://$Server/CN=IP,CN=Inter-Site Transports,CN=Sites,$ConfigNC"
        $ipTransportEntry = [System.DirectoryServices.DirectoryEntry]::new($ipTransportPath)
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($ipTransportEntry)
        $searcher.Filter = "(objectClass=siteLink)"
        $searcher.PropertiesToLoad.Add('name') | Out-Null
        $searcher.PageSize = 1000

        $results = $searcher.FindAll()

        foreach ($result in $results) {
            if ($result.Properties['name'].Count -gt 0) {
                $siteLinks += $result.Properties['name'][0].ToString()
            }
        }

        $results.Dispose()
        $searcher.Dispose()
        $ipTransportEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to enumerate site links" `
            -Exception $_.Exception
    }

    return $siteLinks
}
