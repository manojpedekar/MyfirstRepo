function Get-ADDomainTrust {
    <#
    .SYNOPSIS
        Retrieves trust relationships for a domain

    .DESCRIPTION
        Enumerates all trust relationships for the specified domain using LDAP
        to query trustedDomain objects in the System container. This method
        returns ALL trusts, unlike the .NET GetAllTrustRelationships() API
        which may miss some trust types.

        IMPROVEMENTS over original script (lines 225-260):
        - Uses LDAP to get ALL trusts (like Get-ADTrust cmdlet)
        - Better error handling with context
        - Structured output
        - Option to filter by trust direction
        - InventoryID handling moved to caller

    .PARAMETER DomainName
        The domain name to get trusts for (e.g., "contoso.com")

    .PARAMETER Server
        Optional domain controller to query. If not specified, uses domain name.

    .PARAMETER TrustDirection
        Optional filter for trust direction:
        - Inbound: Only inbound trusts
        - Outbound: Only outbound trusts
        - Bidirectional: Only bidirectional trusts
        - All: All trusts (default)

    .PARAMETER IncludeDisabled
        If specified, includes disabled trusts

    .OUTPUTS
        Array of PSCustomObject with properties:
        - SourceDomain: The source domain name
        - TargetDomain: The target/trusted domain name
        - TrustType: Type of trust (ParentChild, External, Forest, etc.)
        - TrustDirection: Direction (Inbound, Outbound, Bidirectional)
        - TrustAttributes: Trust attributes bitmask
        - IsTransitive: Boolean indicating if trust is transitive
        - WhenCreated: When trust was created (if available)
        - FlatName: NetBIOS name of trusted domain

    .EXAMPLE
        $trusts = Get-ADDomainTrust -DomainName "contoso.com"
        foreach ($trust in $trusts) {
            Write-Host "$($trust.SourceDomain) -> $($trust.TargetDomain) [$($trust.TrustType)]"
        }

    .EXAMPLE
        # Get only inbound and bidirectional trusts
        $trusts = Get-ADDomainTrust -DomainName "contoso.com" -TrustDirection Inbound, Bidirectional

    .NOTES
        Part of SSNC.ADInventory module

        Trust Types (trustType attribute):
        1 = Downlevel (Windows NT domain)
        2 = Uplevel (Windows 2000+ domain)
        3 = MIT (Kerberos realm)
        4 = DCE

        Trust Directions (trustDirection attribute):
        0 = Disabled
        1 = Inbound (this domain trusts the other)
        2 = Outbound (the other domain trusts this)
        3 = Bidirectional (mutual trust)

        Trust Attributes (trustAttributes bitmask):
        0x00000001 = Non-Transitive
        0x00000002 = Uplevel clients only
        0x00000004 = Quarantined Domain (SID filtering)
        0x00000008 = Forest Transitive
        0x00000010 = Cross-Organization
        0x00000020 = Within Forest
        0x00000040 = Treat as External
        0x00000080 = Uses RC4 Encryption
        0x00000200 = Cross-Organization No TGT Delegation
        0x00000400 = PIM Trust
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Inbound', 'Outbound', 'Bidirectional', 'All')]
        [string[]]$TrustDirection = @('All'),

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDisabled
    )

    process {
        Write-ADInventoryLog -Level Info -Message "Retrieving domain trusts via LDAP" `
            -Context @{ DomainName = $DomainName }

        try {
            # Build the search base for the System container
            $domainDN = "DC=" + ($DomainName -replace '\.', ',DC=')
            $systemContainer = "CN=System,$domainDN"

            # Determine server to connect to
            $ldapServer = if ($Server) { $Server } else { $DomainName }

            Write-ADInventoryLog -Level Debug -Message "Searching for trustedDomain objects" `
                -Context @{
                    SearchBase = $systemContainer
                    Server = $ldapServer
                }

            # Create DirectorySearcher for trustedDomain objects
            $ldapPath = "LDAP://$ldapServer/$systemContainer"
            $searchRoot = [System.DirectoryServices.DirectoryEntry]::new($ldapPath)
            $searcher = [System.DirectoryServices.DirectorySearcher]::new($searchRoot)
            $searcher.Filter = "(objectClass=trustedDomain)"
            $searcher.PageSize = 1000

            # Properties to retrieve
            $propertiesToLoad = @(
                'name',
                'trustPartner',
                'flatName',
                'trustDirection',
                'trustType',
                'trustAttributes',
                'whenCreated'
            )
            foreach ($prop in $propertiesToLoad) {
                [void]$searcher.PropertiesToLoad.Add($prop)
            }

            # Execute search
            $searchResults = $searcher.FindAll()
            $results = [System.Collections.ArrayList]::new()

            foreach ($result in $searchResults) {
                try {
                    $props = $result.Properties

                    # Get trust direction (0=Disabled, 1=Inbound, 2=Outbound, 3=Bidirectional)
                    $trustDirValue = if ($props['trustdirection'].Count -gt 0) {
                        [int]$props['trustdirection'][0]
                    } else { 0 }

                    # Skip disabled trusts unless requested
                    if ($trustDirValue -eq 0 -and -not $IncludeDisabled) {
                        continue
                    }

                    # Map direction value to string
                    $trustDirString = switch ($trustDirValue) {
                        0 { 'Disabled' }
                        1 { 'Inbound' }
                        2 { 'Outbound' }
                        3 { 'Bidirectional' }
                        default { 'Unknown' }
                    }

                    # Get trust type (1=Downlevel, 2=Uplevel, 3=MIT, 4=DCE)
                    $trustTypeValue = if ($props['trusttype'].Count -gt 0) {
                        [int]$props['trusttype'][0]
                    } else { 0 }

                    # Get trust attributes bitmask
                    $trustAttrs = if ($props['trustattributes'].Count -gt 0) {
                        [int]$props['trustattributes'][0]
                    } else { 0 }

                    # Determine trust type string and transitivity
                    # FOREST_TRANSITIVE = 0x00000008
                    # NON_TRANSITIVE = 0x00000001
                    # WITHIN_FOREST = 0x00000020
                    $isForestTransitive = ($trustAttrs -band 0x00000008) -ne 0
                    $isNonTransitive = ($trustAttrs -band 0x00000001) -ne 0
                    $isWithinForest = ($trustAttrs -band 0x00000020) -ne 0

                    # Determine trust type name
                    $trustTypeName = switch ($trustTypeValue) {
                        1 { 'Downlevel' }  # Windows NT
                        2 {
                            # Uplevel - could be External, Forest, or ParentChild
                            if ($isForestTransitive) { 'Forest' }
                            elseif ($isWithinForest) { 'ParentChild' }
                            else { 'External' }
                        }
                        3 { 'Kerberos' }   # MIT Kerberos
                        4 { 'DCE' }
                        default { 'Unknown' }
                    }

                    # Determine transitivity
                    $isTransitive = -not $isNonTransitive -and ($isForestTransitive -or $isWithinForest)

                    # Get target domain name
                    $targetDomain = if ($props['trustpartner'].Count -gt 0) {
                        $props['trustpartner'][0].ToString()
                    } elseif ($props['name'].Count -gt 0) {
                        $props['name'][0].ToString()
                    } else {
                        'Unknown'
                    }

                    # Get flat name (NetBIOS name)
                    $flatName = if ($props['flatname'].Count -gt 0) {
                        $props['flatname'][0].ToString()
                    } else { $null }

                    # Get creation date
                    $whenCreated = $null
                    if ($props['whencreated'].Count -gt 0) {
                        try {
                            $whenCreated = [DateTime]$props['whencreated'][0]
                        } catch { }
                    }

                    # Create trust object
                    $trustObj = [PSCustomObject]@{
                        SourceDomain    = $DomainName
                        TargetDomain    = $targetDomain
                        TrustType       = $trustTypeName
                        TrustDirection  = $trustDirString
                        TrustAttributes = $trustAttrs
                        IsTransitive    = $isTransitive
                        WhenCreated     = $whenCreated
                        FlatName        = $flatName
                    }

                    # Apply direction filter
                    $include = $false
                    if ($TrustDirection -contains 'All') {
                        $include = $true
                    }
                    else {
                        if ($TrustDirection -contains $trustObj.TrustDirection) {
                            $include = $true
                        }
                        # Also include Bidirectional if either Inbound or Outbound requested
                        if ($trustObj.TrustDirection -eq 'Bidirectional') {
                            if (($TrustDirection -contains 'Inbound') -or ($TrustDirection -contains 'Outbound')) {
                                $include = $true
                            }
                        }
                    }

                    if ($include) {
                        [void]$results.Add($trustObj)
                    }
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Failed to process trust object" `
                        -Exception $_.Exception
                }
            }

            # Cleanup
            $searchResults.Dispose()
            $searcher.Dispose()
            $searchRoot.Dispose()

            # Calculate trust counts by direction for detailed logging
            $inboundCount = @($results | Where-Object { $_.TrustDirection -eq 'Inbound' }).Count
            $outboundCount = @($results | Where-Object { $_.TrustDirection -eq 'Outbound' }).Count
            $bidirectionalCount = @($results | Where-Object { $_.TrustDirection -eq 'Bidirectional' }).Count

            Write-ADInventoryLog -Level Info -Message "Domain trusts retrieved via LDAP" `
                -Context @{
                    DomainName    = $DomainName
                    TrustCount    = $results.Count
                    Inbound       = $inboundCount
                    Outbound      = $outboundCount
                    Bidirectional = $bidirectionalCount
                }

            return $results.ToArray()
        }
        catch [System.DirectoryServices.DirectoryServicesCOMException] {
            Write-ADInventoryLog -Level Error -Message "LDAP error querying trusts" `
                -Context @{ DomainName = $DomainName } `
                -Exception $_.Exception

            throw "LDAP error querying trusts for domain $DomainName : $_"
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to get trusts" `
                -Context @{ DomainName = $DomainName } `
                -Exception $_.Exception

            # Return empty array instead of throwing (domain may have no trusts)
            return @()
        }
    }
}
