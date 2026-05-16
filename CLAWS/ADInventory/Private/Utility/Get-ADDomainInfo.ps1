function Get-ADDomainInfo {
    <#
    .SYNOPSIS
        Retrieves comprehensive domain information including FSMO roles

    .DESCRIPTION
        Queries Active Directory to collect domain-level information including:
        - Domain identity (SID, GUID, DNS name, NetBIOS name)
        - Functional level
        - FSMO role holders (PDC Emulator, RID Master, Infrastructure Master)
        - Domain controllers and RODCs
        - Parent/child domain relationships

    .PARAMETER DomainName
        The domain name to get information for (e.g., "contoso.com")

    .PARAMETER Server
        Optional domain controller to query. If not specified, uses domain name.

    .OUTPUTS
        PSCustomObject with domain properties

    .EXAMPLE
        $domainInfo = Get-ADDomainInfo -DomainName "contoso.com"

    .NOTES
        Part of SSNC.ADInventory module

        Domain Functional Levels (msDS-Behavior-Version):
        0 = Windows 2000
        1 = Windows Server 2003 Interim
        2 = Windows Server 2003
        3 = Windows Server 2008
        4 = Windows Server 2008 R2
        5 = Windows Server 2012
        6 = Windows Server 2012 R2
        7 = Windows Server 2016
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [string]$Server
    )

    process {
        Write-ADInventoryLog -Level Info -Message "Retrieving domain information" `
            -Context @{ DomainName = $DomainName }

        try {
            # Build the domain DN
            $domainDN = "DC=" + ($DomainName -replace '\.', ',DC=')
            $ldapServer = if ($Server) { $Server } else { $DomainName }

            Write-ADInventoryLog -Level Debug -Message "Querying domain object" `
                -Context @{ DomainDN = $domainDN; Server = $ldapServer }

            # Query the domain object for core properties
            $domainLdapPath = "LDAP://$ldapServer/$domainDN"
            $domainEntry = [System.DirectoryServices.DirectoryEntry]::new($domainLdapPath)
            $domainEntry.RefreshCache(@(
                'objectSid', 'objectGUID', 'name', 'whenCreated', 'whenChanged',
                'msDS-Behavior-Version', 'dc', 'distinguishedName'
            ))

            # Extract domain SID
            $domainSID = $null
            if ($domainEntry.Properties['objectSid'].Count -gt 0) {
                $sidBytes = $domainEntry.Properties['objectSid'][0]
                $sid = [System.Security.Principal.SecurityIdentifier]::new($sidBytes, 0)
                $domainSID = $sid.Value
            }

            # Extract domain GUID
            $domainGUID = $null
            if ($domainEntry.Properties['objectGUID'].Count -gt 0) {
                $guidBytes = $domainEntry.Properties['objectGUID'][0]
                $domainGUID = ([guid]$guidBytes).ToString()
            }

            # Get functional level
            $domainModeLevel = if ($domainEntry.Properties['msDS-Behavior-Version'].Count -gt 0) {
                [int]$domainEntry.Properties['msDS-Behavior-Version'][0]
            } else { -1 }

            $domainMode = Get-FunctionalLevelName -Level $domainModeLevel -Type 'Domain'

            # Get timestamps
            $whenCreated = $null
            $whenChanged = $null
            if ($domainEntry.Properties['whenCreated'].Count -gt 0) {
                $whenCreated = [DateTime]$domainEntry.Properties['whenCreated'][0]
            }
            if ($domainEntry.Properties['whenChanged'].Count -gt 0) {
                $whenChanged = [DateTime]$domainEntry.Properties['whenChanged'][0]
            }

            $domainEntry.Dispose()

            # Get NetBIOS name from Partitions container
            $netBIOSName = Get-DomainNetBIOSName -DomainDN $domainDN -Server $ldapServer

            # Get FSMO role holders
            $fsmoRoles = Get-DomainFSMORoles -DomainDN $domainDN -Server $ldapServer

            # Get forest name (from RootDSE)
            $forestName = Get-ForestNameFromRootDSE -Server $ldapServer

            # Get parent domain (if child domain)
            $parentDomain = Get-ParentDomainName -DomainName $DomainName -ForestName $forestName

            # Get domain controllers
            $dcInfo = Get-DomainControllerList -DomainDN $domainDN -Server $ldapServer

            # Get child domains
            $childDomains = Get-ChildDomainList -DomainDN $domainDN -Server $ldapServer

            $result = [PSCustomObject]@{
                DomainName                      = $DomainName
                DomainSID                       = $domainSID
                DomainGUID                      = $domainGUID
                NetBIOSName                     = $netBIOSName
                DistinguishedName               = $domainDN
                ForestName                      = $forestName
                ParentDomain                    = $parentDomain
                DomainMode                      = $domainMode
                DomainModeLevel                 = $domainModeLevel
                PDCEmulator                     = $fsmoRoles.PDCEmulator
                RIDMaster                       = $fsmoRoles.RIDMaster
                InfrastructureMaster            = $fsmoRoles.InfrastructureMaster
                ChildDomains                    = if ($childDomains.Count -gt 0) { $childDomains | ConvertTo-Json -Compress } else { $null }
                DomainControllers               = if ($dcInfo.DCs.Count -gt 0) { $dcInfo.DCs | ConvertTo-Json -Compress } else { $null }
                ReadOnlyReplicaDirectoryServers = if ($dcInfo.RODCs.Count -gt 0) { $dcInfo.RODCs | ConvertTo-Json -Compress } else { $null }
                WhenCreated                     = $whenCreated
                WhenChanged                     = $whenChanged
            }

            Write-ADInventoryLog -Level Info -Message "Domain information retrieved" `
                -Context @{
                    DomainName = $DomainName
                    DomainSID = $domainSID
                    DomainMode = $domainMode
                    DCCount = $dcInfo.DCs.Count
                }

            return $result
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to get domain information" `
                -Context @{ DomainName = $DomainName } `
                -Exception $_.Exception
            throw "Failed to get domain information for $DomainName : $_"
        }
    }
}

function Get-FunctionalLevelName {
    <#
    .SYNOPSIS
        Converts functional level number to name
    #>
    [CmdletBinding()]
    param(
        [int]$Level,
        [ValidateSet('Domain', 'Forest')]
        [string]$Type = 'Domain'
    )

    $domainLevels = @{
        0 = 'Windows2000'
        1 = 'Windows2003Interim'
        2 = 'Windows2003'
        3 = 'Windows2008'
        4 = 'Windows2008R2'
        5 = 'Windows2012'
        6 = 'Windows2012R2'
        7 = 'Windows2016'
        8 = 'Windows2019'  # Officially still 7 in some docs
        9 = 'Windows2025'
    }

    $forestLevels = @{
        0 = 'Windows2000'
        1 = 'Windows2003Interim'
        2 = 'Windows2003'
        3 = 'Windows2008'
        4 = 'Windows2008R2'
        5 = 'Windows2012'
        6 = 'Windows2012R2'
        7 = 'Windows2016'
        8 = 'Windows2019'
        9 = 'Windows2025'
    }

    $levels = if ($Type -eq 'Forest') { $forestLevels } else { $domainLevels }

    if ($levels.ContainsKey($Level)) {
        return $levels[$Level]
    }
    return "Unknown ($Level)"
}

function Get-DomainNetBIOSName {
    <#
    .SYNOPSIS
        Gets the NetBIOS name for a domain from the Partitions container
    #>
    [CmdletBinding()]
    param(
        [string]$DomainDN,
        [string]$Server
    )

    try {
        # Get configuration NC
        $rootDSE = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/RootDSE")
        $configNC = $rootDSE.Properties['configurationNamingContext'][0].ToString()
        $rootDSE.Dispose()

        # Search Partitions container for crossRef with matching nCName
        $partitionsPath = "LDAP://$Server/CN=Partitions,$configNC"
        $partitionsEntry = [System.DirectoryServices.DirectoryEntry]::new($partitionsPath)
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($partitionsEntry)
        $searcher.Filter = "(&(objectClass=crossRef)(nCName=$DomainDN))"
        $searcher.PropertiesToLoad.Add('netBIOSName') | Out-Null

        $result = $searcher.FindOne()
        $netBIOSName = $null

        if ($result -and $result.Properties['netbiosname'].Count -gt 0) {
            $netBIOSName = $result.Properties['netbiosname'][0].ToString()
        }

        $searcher.Dispose()
        $partitionsEntry.Dispose()

        return $netBIOSName
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to get NetBIOS name" `
            -Context @{ DomainDN = $DomainDN } `
            -Exception $_.Exception
        return $null
    }
}

function Get-DomainFSMORoles {
    <#
    .SYNOPSIS
        Gets the domain-level FSMO role holders
    #>
    [CmdletBinding()]
    param(
        [string]$DomainDN,
        [string]$Server
    )

    $roles = @{
        PDCEmulator = $null
        RIDMaster = $null
        InfrastructureMaster = $null
    }

    try {
        # PDC Emulator - fSMORoleOwner on domain NC
        $domainEntry = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$DomainDN")
        $domainEntry.RefreshCache(@('fSMORoleOwner'))
        if ($domainEntry.Properties['fSMORoleOwner'].Count -gt 0) {
            $roles.PDCEmulator = Extract-ServerFromNTDSDSA $domainEntry.Properties['fSMORoleOwner'][0].ToString()
        }
        $domainEntry.Dispose()

        # RID Master - fSMORoleOwner on CN=RID Manager$,CN=System
        $ridManagerPath = "LDAP://$Server/CN=RID Manager`$,CN=System,$DomainDN"
        $ridManagerEntry = [System.DirectoryServices.DirectoryEntry]::new($ridManagerPath)
        $ridManagerEntry.RefreshCache(@('fSMORoleOwner'))
        if ($ridManagerEntry.Properties['fSMORoleOwner'].Count -gt 0) {
            $roles.RIDMaster = Extract-ServerFromNTDSDSA $ridManagerEntry.Properties['fSMORoleOwner'][0].ToString()
        }
        $ridManagerEntry.Dispose()

        # Infrastructure Master - fSMORoleOwner on CN=Infrastructure
        $infraPath = "LDAP://$Server/CN=Infrastructure,$DomainDN"
        $infraEntry = [System.DirectoryServices.DirectoryEntry]::new($infraPath)
        $infraEntry.RefreshCache(@('fSMORoleOwner'))
        if ($infraEntry.Properties['fSMORoleOwner'].Count -gt 0) {
            $roles.InfrastructureMaster = Extract-ServerFromNTDSDSA $infraEntry.Properties['fSMORoleOwner'][0].ToString()
        }
        $infraEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to get some FSMO roles" `
            -Context @{ DomainDN = $DomainDN } `
            -Exception $_.Exception
    }

    return $roles
}

function Extract-ServerFromNTDSDSA {
    <#
    .SYNOPSIS
        Extracts server name from NTDS Settings DN
    #>
    [CmdletBinding()]
    param([string]$NtdsDsaDN)

    # NTDS Settings DN format: CN=NTDS Settings,CN=ServerName,CN=Servers,CN=SiteName,CN=Sites,CN=Configuration,DC=...
    if ([string]::IsNullOrEmpty($NtdsDsaDN)) { return $null }

    try {
        $parts = $NtdsDsaDN -split ','
        foreach ($part in $parts) {
            if ($part -match '^CN=(.+)$' -and $part -notmatch 'NTDS Settings|Servers|Sites|Configuration') {
                return $Matches[1]
            }
        }
    }
    catch { }

    return $NtdsDsaDN
}

function Get-ForestNameFromRootDSE {
    <#
    .SYNOPSIS
        Gets the forest name from RootDSE
    #>
    [CmdletBinding()]
    param([string]$Server)

    try {
        $rootDSE = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/RootDSE")
        $forestDN = $rootDSE.Properties['rootDomainNamingContext'][0].ToString()
        $rootDSE.Dispose()

        # Convert DN to DNS name
        $forestName = ($forestDN -replace 'DC=', '' -replace ',', '.').TrimStart('.')
        return $forestName
    }
    catch {
        return $null
    }
}

function Get-ParentDomainName {
    <#
    .SYNOPSIS
        Gets the parent domain name if this is a child domain
    #>
    [CmdletBinding()]
    param(
        [string]$DomainName,
        [string]$ForestName
    )

    # If domain equals forest, it's the root - no parent
    if ($DomainName -eq $ForestName) {
        return $null
    }

    # Parent is the next level up in the DNS hierarchy
    $parts = $DomainName -split '\.'
    if ($parts.Count -gt 1) {
        $parentParts = $parts[1..($parts.Count - 1)]
        return $parentParts -join '.'
    }

    return $null
}

function Get-DomainControllerList {
    <#
    .SYNOPSIS
        Gets list of domain controllers for a domain
    #>
    [CmdletBinding()]
    param(
        [string]$DomainDN,
        [string]$Server
    )

    $result = @{
        DCs = @()
        RODCs = @()
    }

    try {
        # Search for computer objects with userAccountControl containing SERVER_TRUST_ACCOUNT
        $domainEntry = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$DomainDN")
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($domainEntry)
        # Filter for domain controllers (userAccountControl has SERVER_TRUST_ACCOUNT bit = 8192)
        $searcher.Filter = "(&(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=8192))"
        $searcher.PropertiesToLoad.Add('name') | Out-Null
        $searcher.PropertiesToLoad.Add('dNSHostName') | Out-Null
        $searcher.PropertiesToLoad.Add('primaryGroupID') | Out-Null
        $searcher.PageSize = 1000

        $searchResults = $searcher.FindAll()

        foreach ($dcResult in $searchResults) {
            $dcName = if ($dcResult.Properties['dnshostname'].Count -gt 0) {
                $dcResult.Properties['dnshostname'][0].ToString()
            } elseif ($dcResult.Properties['name'].Count -gt 0) {
                $dcResult.Properties['name'][0].ToString()
            } else { continue }

            # Check if RODC (primaryGroupID = 521 for RODCs)
            $primaryGroupID = if ($dcResult.Properties['primarygroupid'].Count -gt 0) {
                [int]$dcResult.Properties['primarygroupid'][0]
            } else { 516 }  # Default DC group

            if ($primaryGroupID -eq 521) {
                $result.RODCs += $dcName
            } else {
                $result.DCs += $dcName
            }
        }

        $searchResults.Dispose()
        $searcher.Dispose()
        $domainEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to enumerate domain controllers" `
            -Context @{ DomainDN = $DomainDN } `
            -Exception $_.Exception
    }

    return $result
}

function Get-ChildDomainList {
    <#
    .SYNOPSIS
        Gets list of child domains
    #>
    [CmdletBinding()]
    param(
        [string]$DomainDN,
        [string]$Server
    )

    $childDomains = @()

    try {
        # Get configuration NC
        $rootDSE = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/RootDSE")
        $configNC = $rootDSE.Properties['configurationNamingContext'][0].ToString()
        $rootDSE.Dispose()

        # Search Partitions for domains where this domain is the parent
        $partitionsPath = "LDAP://$Server/CN=Partitions,$configNC"
        $partitionsEntry = [System.DirectoryServices.DirectoryEntry]::new($partitionsPath)
        $searcher = [System.DirectoryServices.DirectorySearcher]::new($partitionsEntry)
        $searcher.Filter = "(&(objectClass=crossRef)(systemFlags:1.2.840.113556.1.4.803:=3))"
        $searcher.PropertiesToLoad.Add('dnsRoot') | Out-Null
        $searcher.PropertiesToLoad.Add('nCName') | Out-Null
        $searcher.PageSize = 100

        $results = $searcher.FindAll()

        # Convert this domain DN to comparable format
        $thisDomainDNLower = $DomainDN.ToLower()

        foreach ($partResult in $results) {
            $ncName = if ($partResult.Properties['ncname'].Count -gt 0) {
                $partResult.Properties['ncname'][0].ToString()
            } else { continue }

            $dnsRoot = if ($partResult.Properties['dnsroot'].Count -gt 0) {
                $partResult.Properties['dnsroot'][0].ToString()
            } else { continue }

            # Check if this domain's DN is a parent of ncName (child ends with parent DN)
            if ($ncName.ToLower().EndsWith(",$thisDomainDNLower") -and $ncName.ToLower() -ne $thisDomainDNLower) {
                $childDomains += $dnsRoot
            }
        }

        $results.Dispose()
        $searcher.Dispose()
        $partitionsEntry.Dispose()
    }
    catch {
        Write-ADInventoryLog -Level Debug -Message "Failed to enumerate child domains" `
            -Context @{ DomainDN = $DomainDN } `
            -Exception $_.Exception
    }

    return $childDomains
}
