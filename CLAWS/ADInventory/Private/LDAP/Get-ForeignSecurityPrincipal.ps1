function Get-ForeignSecurityPrincipal {
    <#
    .SYNOPSIS
        Retrieves Foreign Security Principals (FSPs) from a domain with optional cross-domain resolution

    .DESCRIPTION
        Enumerates Foreign Security Principals in the specified domain. FSPs represent
        security principals from external trusted domains.

        IMPROVEMENTS over original script (lines 262-340):
        - Original: Collected FSPs but didn't resolve them (line 322 comment)
        - Enhanced: Optional cross-domain resolution to identify actual objects
        - Structured output with resolved information

        FSPs are stored in CN=ForeignSecurityPrincipals,DC=domain,DC=com
        The CN attribute contains the SID of the external principal.

    .PARAMETER Server
        The domain controller to query

    .PARAMETER DomainName
        The domain name to query for FSPs

    .PARAMETER Config
        ADQueryConfig object containing connection settings and credentials

    .PARAMETER ResolveForeignDomain
        If specified, attempts to resolve the FSP to its actual object in the foreign domain
        This requires connectivity to the trusted domain

    .PARAMETER TrustMap
        Optional hashtable mapping domain SIDs to domain names for resolution
        Key: Domain SID (first part of FSP SID)
        Value: Domain FQDN

    .OUTPUTS
        Array of PSCustomObject with properties:
        - SID: The SID of the foreign principal
        - SID_String: String representation of SID
        - DN: Distinguished name of the FSP in this domain
        - SourceDomain: The domain this FSP belongs to (if resolved)
        - ResolvedName: The actual name in the source domain (if resolved)
        - ResolvedType: The object type in source domain (User, Group, Computer) (if resolved)
        - WhenCreated: When FSP was created in this domain

    .EXAMPLE
        # Get FSPs without resolution
        $fsps = Get-ForeignSecurityPrincipal `
            -Server "dc01.contoso.com" `
            -DomainName "contoso.com" `
            -Config $config

    .EXAMPLE
        # Get FSPs with cross-domain resolution
        $trustMap = @{
            'S-1-5-21-1234567890-1234567890-1234567890' = 'fabrikam.com'
            'S-1-5-21-9876543210-9876543210-9876543210' = 'trusted.com'
        }
        $fsps = Get-ForeignSecurityPrincipal `
            -Server "dc01.contoso.com" `
            -DomainName "contoso.com" `
            -Config $config `
            -ResolveForeignDomain `
            -TrustMap $trustMap

    .NOTES
        Part of SSNC.ADInventory module

        Foreign Security Principals:
        - Created automatically when external principals are added to local groups
        - Stored in CN=ForeignSecurityPrincipals container
        - CN attribute contains the SID
        - Used for cross-domain group memberships

        Performance Considerations:
        - Resolution requires connectivity to each trusted domain
        - Each FSP resolution is a separate LDAP query
        - Consider caching resolved FSPs
        - Use TrustMap to avoid domain SID lookups

        Error Handling:
        - Returns empty array if no FSPs found
        - Logs warnings for resolution failures
        - Continues processing if individual FSP resolution fails
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [ADQueryConfig]$Config = [ADQueryConfig]::new(),

        [Parameter(Mandatory = $false)]
        [switch]$ResolveForeignDomain,

        [Parameter(Mandatory = $false)]
        [hashtable]$TrustMap = @{}
    )

    process {
        Write-ADInventoryLog -Level Info -Message "Retrieving Foreign Security Principals" `
            -Context @{
                DomainName = $DomainName
                Server = $Server
                ResolveForeignDomain = $ResolveForeignDomain.IsPresent
            }

        $results = [System.Collections.ArrayList]::new()

        try {
            # Build FSP container path
            $domainDN = "DC=" + ($DomainName -replace '\.', ',DC=')
            $fspContainer = "CN=ForeignSecurityPrincipals,$domainDN"

            # Build LDAP filter for FSPs
            $filter = "(objectClass=foreignSecurityPrincipal)"

            # Properties to retrieve
            $properties = @(
                'cn',
                'objectSid',
                'distinguishedName',
                'whenCreated',
                'name'
            )

            Write-ADInventoryLog -Level Debug -Message "Querying FSP container" `
                -Context @{
                    Container = $fspContainer
                    Filter = $filter
                }

            # Create directory searcher
            $de = $null
            $ds = $null

            try {
                $ldapPath = "LDAP://$Server/$fspContainer"
                $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)

                # Apply credentials if provided
                if ($Config.Credential) {
                    $de.Username = $Config.Credential.UserName
                    $de.Password = $Config.Credential.GetNetworkCredential().Password
                }

                $ds = New-Object System.DirectoryServices.DirectorySearcher($de)
                $ds.Filter = $filter
                $ds.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
                $ds.PageSize = $Config.PageSize
                $ds.ServerTimeLimit = [TimeSpan]::FromMinutes($Config.ServerTimeoutMinutes)
                $ds.ClientTimeout = [TimeSpan]::FromMinutes($Config.ClientTimeoutMinutes)

                # Add properties to load
                foreach ($prop in $properties) {
                    [void]$ds.PropertiesToLoad.Add($prop)
                }

                # Execute search
                $searchResults = $null
                try {
                    $searchResults = $ds.FindAll()

                    Write-ADInventoryLog -Level Debug -Message "FSPs found" `
                        -Context @{
                            DomainName = $DomainName
                            Count = $searchResults.Count
                        }

                    foreach ($result in $searchResults) {
                        try {
                            # Extract SID
                            $sidBytes = $result.Properties['objectSid'][0]
                            $sidString = ConvertTo-SidString -Value $sidBytes

                            if ([string]::IsNullOrEmpty($sidString)) {
                                Write-ADInventoryLog -Level Warning -Message "FSP has no valid SID" `
                                    -Context @{ DN = $result.Properties['distinguishedName'][0] }
                                continue
                            }

                            # Create FSP object
                            $fspObj = [PSCustomObject]@{
                                SID = $sidBytes
                                SID_String = $sidString
                                DN = $result.Properties['distinguishedName'][0]
                                SourceDomain = $null
                                ResolvedName = $null
                                ResolvedType = $null
                                ResolvedDN = $null
                                WhenCreated = ConvertTo-DateTimeFromFileTime -Value $result.Properties['whenCreated'][0]
                            }

                            # Resolve foreign domain if requested
                            if ($ResolveForeignDomain) {
                                $resolved = Resolve-ForeignSecurityPrincipal `
                                    -SID $sidString `
                                    -TrustMap $TrustMap `
                                    -Config $Config

                                if ($resolved) {
                                    $fspObj.SourceDomain = $resolved.DomainName
                                    $fspObj.ResolvedName = $resolved.Name
                                    $fspObj.ResolvedType = $resolved.ObjectType
                                    $fspObj.ResolvedDN = $resolved.DistinguishedName
                                }
                            }

                            [void]$results.Add($fspObj)
                        }
                        catch {
                            Write-ADInventoryLog -Level Warning -Message "Failed to process FSP" `
                                -Context @{ DN = $result.Properties['distinguishedName'][0] } `
                                -Exception $_.Exception
                            # Continue with next FSP
                        }
                    }
                }
                finally {
                    if ($searchResults) {
                        $searchResults.Dispose()
                    }
                }
            }
            finally {
                if ($ds) { $ds.Dispose() }
                if ($de) { $de.Dispose() }
            }

            Write-ADInventoryLog -Level Info -Message "FSPs retrieved successfully" `
                -Context @{
                    DomainName = $DomainName
                    TotalFSPs = $results.Count
                    ResolvedFSPs = ($results | Where-Object { $_.ResolvedName }).Count
                }

            return $results.ToArray()
        }
        catch [System.DirectoryServices.DirectoryServicesCOMException] {
            # FSP container may not exist (no cross-domain memberships)
            Write-ADInventoryLog -Level Debug -Message "FSP container not accessible" `
                -Context @{
                    DomainName = $DomainName
                    Container = $fspContainer
                } `
                -Exception $_.Exception

            return @()
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to retrieve FSPs" `
                -Context @{
                    DomainName = $DomainName
                    Server = $Server
                } `
                -Exception $_.Exception

            return @()
        }
    }
}

function Resolve-ForeignSecurityPrincipal {
    <#
    .SYNOPSIS
        Resolves a Foreign Security Principal SID to its actual object in the source domain

    .DESCRIPTION
        Internal helper function to resolve FSP SIDs to their actual objects
        in trusted domains. Extracts domain SID, determines domain FQDN,
        and queries the source domain for the object.

    .PARAMETER SID
        The SID string of the foreign principal (e.g., "S-1-5-21-...")

    .PARAMETER TrustMap
        Hashtable mapping domain SIDs to domain FQDNs

    .PARAMETER Config
        ADQueryConfig object for connection settings

    .OUTPUTS
        PSCustomObject with DomainName, Name, ObjectType, DistinguishedName
        Returns $null if resolution fails

    .NOTES
        Internal function - not exported
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SID,

        [Parameter(Mandatory = $true)]
        [hashtable]$TrustMap,

        [Parameter(Mandatory = $true)]
        [ADQueryConfig]$Config
    )

    process {
        try {
            # Extract domain SID from object SID
            # SID format: S-1-5-21-domain1-domain2-domain3-RID
            # Domain SID: S-1-5-21-domain1-domain2-domain3
            $sidParts = $SID -split '-'
            if ($sidParts.Count -lt 8) {
                # Not a domain SID (e.g., built-in SID)
                Write-ADInventoryLog -Level Debug -Message "SID is not a domain SID" `
                    -Context @{ SID = $SID }
                return $null
            }

            # Rebuild domain SID (all parts except the last RID)
            $domainSid = ($sidParts[0..($sidParts.Count - 2)] -join '-')

            Write-ADInventoryLog -Level Verbose -Message "Resolving FSP" `
                -Context @{
                    ObjectSID = $SID
                    DomainSID = $domainSid
                }

            # Lookup domain name from trust map
            if (-not $TrustMap.ContainsKey($domainSid)) {
                Write-ADInventoryLog -Level Debug -Message "Domain SID not in trust map" `
                    -Context @{ DomainSID = $domainSid }
                return $null
            }

            $sourceDomain = $TrustMap[$domainSid]

            Write-ADInventoryLog -Level Verbose -Message "Querying source domain for FSP" `
                -Context @{
                    SID = $SID
                    SourceDomain = $sourceDomain
                }

            # Query source domain for object
            $domainDN = "DC=" + ($sourceDomain -replace '\.', ',DC=')
            $ldapPath = "LDAP://$sourceDomain/$domainDN"

            $de = $null
            $ds = $null

            try {
                $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)

                if ($Config.Credential) {
                    $de.Username = $Config.Credential.UserName
                    $de.Password = $Config.Credential.GetNetworkCredential().Password
                }

                $ds = New-Object System.DirectoryServices.DirectorySearcher($de)
                $ds.Filter = "(objectSid=$SID)"
                $ds.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
                $ds.PropertiesToLoad.AddRange(@('name', 'objectClass', 'distinguishedName'))
                $ds.SizeLimit = 1

                $result = $ds.FindOne()

                if ($result) {
                    # Determine object type
                    $objectClasses = $result.Properties['objectClass']
                    $objectType = 'Unknown'
                    if ($objectClasses -contains 'user') { $objectType = 'User' }
                    elseif ($objectClasses -contains 'group') { $objectType = 'Group' }
                    elseif ($objectClasses -contains 'computer') { $objectType = 'Computer' }

                    $resolved = [PSCustomObject]@{
                        DomainName = $sourceDomain
                        Name = $result.Properties['name'][0]
                        ObjectType = $objectType
                        DistinguishedName = $result.Properties['distinguishedName'][0]
                    }

                    Write-ADInventoryLog -Level Verbose -Message "FSP resolved successfully" `
                        -Context @{
                            SID = $SID
                            SourceDomain = $sourceDomain
                            Name = $resolved.Name
                            Type = $objectType
                        }

                    return $resolved
                }
                else {
                    Write-ADInventoryLog -Level Debug -Message "FSP object not found in source domain" `
                        -Context @{
                            SID = $SID
                            SourceDomain = $sourceDomain
                        }
                    return $null
                }
            }
            finally {
                if ($ds) { $ds.Dispose() }
                if ($de) { $de.Dispose() }
            }
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "Failed to resolve FSP" `
                -Context @{ SID = $SID } `
                -Exception $_.Exception

            return $null
        }
    }
}
