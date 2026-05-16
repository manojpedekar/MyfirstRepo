<#
.SYNOPSIS
    Collects AD FS and Device Registration Service configuration from Active Directory.

.DESCRIPTION
    Queries the Configuration partition for AD FS (Active Directory Federation Services)
    and Device Registration Service (DRS) Service Connection Points.

    AD FS registers Service Connection Points in AD that contain:
    - Azure AD tenant information (for hybrid identity scenarios)
    - Federation service names
    - Service bindings

    Device Registration Service (DRS) is used for:
    - Azure AD Join
    - Hybrid Azure AD Join
    - Device registration for Conditional Access

.PARAMETER Server
    IP address or hostname of a domain controller to query.

.PARAMETER ForestName
    The forest name (DNS root domain name).

.PARAMETER Config
    Optional ADQueryConfig object with query settings.

.OUTPUTS
    Array of PSCustomObject with the following properties:
    - ForestName: The forest name
    - ServiceType: 'ADFS' or 'DRS' (Device Registration)
    - ServiceName: The service CN
    - FederationServiceName: Federation service name (ADFS only)
    - AzureTenantId: Azure AD tenant ID (from keywords)
    - AzureObjectId: Azure AD object ID (from keywords)
    - DomainName: Associated domain name
    - ServiceBindingInfo: Service URL or binding information
    - Keywords: JSON array of all keywords
    - DistinguishedName: Full DN of the SCP
    - ObjectGUID: Object GUID
    - WhenCreated: Creation timestamp
    - WhenChanged: Last modification timestamp

.NOTES
    Part of SSNC.ADInventory module
    Forest-scoped data - collect once per forest

    LDAP Locations:
    - ADFS SCPs: CN=ADFS,CN=Microsoft,CN=Program Data,CN=Configuration,{ForestDN}
    - DRS SCPs: CN=Device Registration Configuration,CN=Services,CN=Configuration,{ForestDN}

    Keywords Parsing:
    The keywords attribute contains key-value pairs like:
    - azureADName:{tenant-name}
    - azureADId:{tenant-id}
    - azureADObjectId:{object-id}

.EXAMPLE
    Get-ADFSConfigurationInfo -Server "dc01.contoso.com" -ForestName "contoso.com"
    Returns all ADFS and DRS configuration for the forest.
#>
function Get-ADFSConfigurationInfo {
    [CmdletBinding()]
    [OutputType([array])]
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
        $adfsConfigs = [System.Collections.ArrayList]::new()

        Write-ADInventoryLog -Level Info -Message "Collecting AD FS configuration" `
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

            # Collect ADFS Service Connection Points
            $adfsResults = Get-ADFSServiceConnectionPointsInternal -Server $Server -ConfigDn $configDn -Config $Config -ForestName $ForestName
            foreach ($item in $adfsResults) {
                [void]$adfsConfigs.Add($item)
            }

            # Collect Device Registration Service configuration
            $drsResults = Get-DeviceRegistrationServiceInternal -Server $Server -ConfigDn $configDn -Config $Config -ForestName $ForestName
            foreach ($item in $drsResults) {
                [void]$adfsConfigs.Add($item)
            }

            Write-ADInventoryLog -Level Info -Message "AD FS configuration collection completed" `
                -Category Collection `
                -Context @{
                    ForestName = $ForestName
                    TotalRecords = $adfsConfigs.Count
                    ADFSCount = ($adfsConfigs | Where-Object { $_.ServiceType -eq 'ADFS' }).Count
                    DRSCount = ($adfsConfigs | Where-Object { $_.ServiceType -eq 'DRS' }).Count
                }

            return @($adfsConfigs)
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to collect AD FS configuration" `
                -Category Collection `
                -Context @{ Server = $Server; ForestName = $ForestName } `
                -Exception $_.Exception
            return @()
        }
    }
}

#region Internal Helper Functions

function Get-ADFSServiceConnectionPointsInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$ConfigDn,
        [ADQueryConfig]$Config,
        [string]$ForestName
    )

    $results = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        # Search for ADFS SCPs in the Configuration partition
        # Common locations:
        # - CN=ADFS,CN=Microsoft,CN=Program Data,CN=Configuration
        # - Also search broader for any SCP with ADFS-related keywords
        $servicesContainer = "CN=Services,$ConfigDn"

        $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$servicesContainer")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)

        # Search for Service Connection Points with ADFS-related keywords
        # Note: azureADName:* was removed to avoid picking up DRS objects (collected separately)
        # DRS objects only have azureADName/azureADId keywords, not ADFS/FederationService
        $searcher.Filter = "(&(objectClass=serviceConnectionPoint)(|(keywords=*ADFS*)(keywords=*FederationService*)))"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'distinguishedName', 'keywords', 'serviceDNSName',
            'serviceBindingInformation', 'objectGUID', 'whenCreated', 'whenChanged'
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

            # Extract keywords
            $keywords = @()
            if ($props['keywords'] -and $props['keywords'].Count -gt 0) {
                $keywords = @($props['keywords'])
            }

            # Parse Azure AD info from keywords
            $azureTenantId = $null
            $azureObjectId = $null
            $federationServiceName = $null
            $domainName = $null

            foreach ($keyword in $keywords) {
                $kw = [string]$keyword
                if ($kw -match '^azureADId:(.+)$') {
                    $azureTenantId = $Matches[1]
                }
                elseif ($kw -match '^azureADObjectId:(.+)$') {
                    $azureObjectId = $Matches[1]
                }
                elseif ($kw -match '^azureADName:(.+)$') {
                    $domainName = $Matches[1]
                }
                elseif ($kw -match '^FederationServiceName:(.+)$') {
                    $federationServiceName = $Matches[1]
                }
            }

            $serviceBinding = $null
            if ($props['servicebindinginformation'] -and $props['servicebindinginformation'].Count -gt 0) {
                $serviceBinding = [string]$props['servicebindinginformation'][0]
            }

            $record = [PSCustomObject]@{
                ForestName            = $ForestName
                ServiceType           = 'ADFS'
                ServiceName           = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                FederationServiceName = $federationServiceName
                AzureTenantId         = $azureTenantId
                AzureObjectId         = $azureObjectId
                DomainName            = $domainName
                ServiceBindingInfo    = $serviceBinding
                Keywords              = ($keywords | ConvertTo-Json -Compress)
                DistinguishedName     = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID            = $objectGuid
                WhenCreated           = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged           = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }

            [void]$results.Add($record)
        }

        Write-ADInventoryLog -Level Debug -Message "ADFS SCP query completed" `
            -Context @{ Server = $Server; RecordCount = $results.Count }

        return $results.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query ADFS SCPs" `
            -Context @{ Server = $Server } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

function Get-DeviceRegistrationServiceInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$ConfigDn,
        [ADQueryConfig]$Config,
        [string]$ForestName
    )

    $results = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        # DRS is typically at: CN=Device Registration Configuration,CN=Services,CN=Configuration
        $drsContainer = "CN=Device Registration Configuration,CN=Services,$ConfigDn"

        # Check if DRS container exists
        try {
            $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$drsContainer")
            # Force bind to check if it exists
            $null = $searchRoot.distinguishedName
        }
        catch {
            # DRS container doesn't exist - common if DRS not configured
            Write-ADInventoryLog -Level Debug -Message "Device Registration Service container not found" `
                -Context @{ Server = $Server }
            return @()
        }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=serviceConnectionPoint)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'distinguishedName', 'keywords', 'serviceDNSName',
            'serviceBindingInformation', 'objectGUID', 'whenCreated', 'whenChanged'
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

            # Extract keywords
            $keywords = @()
            if ($props['keywords'] -and $props['keywords'].Count -gt 0) {
                $keywords = @($props['keywords'])
            }

            # Parse Azure AD info from keywords
            $azureTenantId = $null
            $azureObjectId = $null
            $domainName = $null

            foreach ($keyword in $keywords) {
                $kw = [string]$keyword
                if ($kw -match '^azureADId:(.+)$') {
                    $azureTenantId = $Matches[1]
                }
                elseif ($kw -match '^azureADObjectId:(.+)$') {
                    $azureObjectId = $Matches[1]
                }
                elseif ($kw -match '^azureADName:(.+)$') {
                    $domainName = $Matches[1]
                }
            }

            $serviceBinding = $null
            if ($props['servicebindinginformation'] -and $props['servicebindinginformation'].Count -gt 0) {
                $serviceBinding = [string]$props['servicebindinginformation'][0]
            }

            $record = [PSCustomObject]@{
                ForestName            = $ForestName
                ServiceType           = 'DRS'
                ServiceName           = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                FederationServiceName = $null
                AzureTenantId         = $azureTenantId
                AzureObjectId         = $azureObjectId
                DomainName            = $domainName
                ServiceBindingInfo    = $serviceBinding
                Keywords              = ($keywords | ConvertTo-Json -Compress)
                DistinguishedName     = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID            = $objectGuid
                WhenCreated           = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged           = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }

            [void]$results.Add($record)
        }

        Write-ADInventoryLog -Level Debug -Message "DRS SCP query completed" `
            -Context @{ Server = $Server; RecordCount = $results.Count }

        return $results.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query DRS SCPs" `
            -Context @{ Server = $Server } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($searchResults) { try { $searchResults.Dispose() } catch { } }
        if ($searcher) { try { $searcher.Dispose() } catch { } }
        if ($searchRoot) { try { $searchRoot.Dispose() } catch { } }
    }
}

#endregion
