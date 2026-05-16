function Get-LargeMultiValuedAttribute {
    <#
    .SYNOPSIS
        Retrieves large multi-valued attributes using range retrieval

    .DESCRIPTION
        Active Directory returns a maximum of 1500 values for multi-valued attributes
        in a single query. For attributes with more values (e.g., groups with >1500 members),
        this function uses range retrieval to fetch all values.

        ADDRESSES limitation from original script (Section 3.3 of technical review):
        - Original: Multi-valued attributes with 1000+ values were truncated
        - Fixed: Automatic range retrieval for large attributes

        Uses the LDAP range retrieval syntax: attribute;range=start-end
        Example: member;range=0-1499, member;range=1500-2999, etc.

    .PARAMETER DistinguishedName
        The distinguished name of the object to query

    .PARAMETER AttributeName
        The name of the multi-valued attribute to retrieve (e.g., "member", "memberOf")

    .PARAMETER Server
        The domain controller to query

    .PARAMETER Config
        ADQueryConfig object containing connection settings and credentials

    .OUTPUTS
        Array of attribute values (strings)

    .EXAMPLE
        # Get all members of a large group
        $members = Get-LargeMultiValuedAttribute `
            -DistinguishedName "CN=AllUsers,OU=Groups,DC=contoso,DC=com" `
            -AttributeName "member" `
            -Server "dc01.contoso.com" `
            -Config $config

    .EXAMPLE
        # Get all memberOf entries for a user
        $memberships = Get-LargeMultiValuedAttribute `
            -DistinguishedName "CN=John Doe,OU=Users,DC=contoso,DC=com" `
            -AttributeName "memberOf" `
            -Server "dc01.contoso.com" `
            -Config $config

    .NOTES
        Part of SSNC.ADInventory module

        Range Retrieval Details:
        - AD returns 1500 values per range request
        - Range syntax: attribute;range=start-end
        - Last range indicated by: attribute;range=start-*
        - Requires separate LDAP query for each range

        Performance Considerations:
        - Each range requires a separate query
        - For 10,000 member group: 7 queries (1500 * 6 + 1000)
        - Use batch processing for multiple large groups

        Error Handling:
        - Returns empty array if object not found
        - Returns empty array if attribute doesn't exist
        - Logs warnings for query failures
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistinguishedName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AttributeName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [ADQueryConfig]$Config = [ADQueryConfig]::new()
    )

    process {
        Write-ADInventoryLog -Level Debug -Message "Retrieving large multi-valued attribute" `
            -Context @{
                DN = $DistinguishedName
                Attribute = $AttributeName
                Server = $Server
            }

        $allValues = [System.Collections.ArrayList]::new()
        $rangeStart = 0
        $rangeSize = 1500  # AD's maximum range size
        $hasMore = $true
        $queryCount = 0

        try {
            while ($hasMore) {
                $queryCount++
                $rangeEnd = $rangeStart + $rangeSize - 1

                # Construct range attribute name
                $rangedAttributeName = "$AttributeName;range=$rangeStart-$rangeEnd"

                Write-ADInventoryLog -Level Verbose -Message "Fetching range" `
                    -Context @{
                        DN = $DistinguishedName
                        Attribute = $AttributeName
                        Range = "$rangeStart-$rangeEnd"
                        QueryNumber = $queryCount
                    }

                # Create directory entry
                $de = $null
                try {
                    $ldapPath = "LDAP://$Server/$DistinguishedName"
                    $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)

                    # Apply credentials if provided
                    if ($Config.Credential) {
                        $de.Username = $Config.Credential.UserName
                        $de.Password = $Config.Credential.GetNetworkCredential().Password
                    }

                    # Force connection to verify object exists
                    $guid = $de.Guid
                    if ([string]::IsNullOrEmpty($guid)) {
                        Write-ADInventoryLog -Level Warning -Message "Object not found" `
                            -Context @{ DN = $DistinguishedName }
                        return @()
                    }

                    # Refresh property cache with ranged attribute
                    $de.RefreshCache(@($rangedAttributeName))

                    # Check which attribute name was actually returned
                    $returnedAttribute = $null
                    foreach ($propName in $de.Properties.PropertyNames) {
                        if ($propName.StartsWith($AttributeName)) {
                            $returnedAttribute = $propName
                            break
                        }
                    }

                    if ($null -eq $returnedAttribute) {
                        # Attribute doesn't exist or has no values
                        Write-ADInventoryLog -Level Debug -Message "Attribute not found or empty" `
                            -Context @{
                                DN = $DistinguishedName
                                Attribute = $AttributeName
                            }
                        $hasMore = $false
                        break
                    }

                    # Get the values
                    $values = $de.Properties[$returnedAttribute]

                    if ($null -eq $values -or $values.Count -eq 0) {
                        # No more values
                        $hasMore = $false
                    }
                    else {
                        # Add values to collection
                        foreach ($value in $values) {
                            [void]$allValues.Add($value)
                        }

                        Write-ADInventoryLog -Level Verbose -Message "Retrieved range values" `
                            -Context @{
                                DN = $DistinguishedName
                                Attribute = $AttributeName
                                Range = "$rangeStart-$rangeEnd"
                                ValuesRetrieved = $values.Count
                                TotalSoFar = $allValues.Count
                            }

                        # Check if this is the last range
                        # Last range is indicated by attribute;range=start-*
                        if ($returnedAttribute -match '\*$') {
                            Write-ADInventoryLog -Level Debug -Message "Last range indicator received" `
                                -Context @{
                                    DN = $DistinguishedName
                                    Attribute = $AttributeName
                                    ReturnedAttribute = $returnedAttribute
                                }
                            $hasMore = $false
                        }
                        elseif ($values.Count -lt $rangeSize) {
                            # Received fewer values than requested = last range
                            Write-ADInventoryLog -Level Debug -Message "Last range (partial) received" `
                                -Context @{
                                    DN = $DistinguishedName
                                    Attribute = $AttributeName
                                    ValuesRetrieved = $values.Count
                                }
                            $hasMore = $false
                        }
                        else {
                            # More ranges to fetch
                            $rangeStart = $rangeEnd + 1
                        }
                    }
                }
                finally {
                    if ($de) {
                        $de.Dispose()
                    }
                }
            }

            Write-ADInventoryLog -Level Info -Message "Large multi-valued attribute retrieved" `
                -Context @{
                    DN = $DistinguishedName
                    Attribute = $AttributeName
                    TotalValues = $allValues.Count
                    QueriesRequired = $queryCount
                }

            return $allValues.ToArray()
        }
        catch [System.DirectoryServices.DirectoryServicesCOMException] {
            Write-ADInventoryLog -Level Warning -Message "Failed to retrieve attribute" `
                -Context @{
                    DN = $DistinguishedName
                    Attribute = $AttributeName
                    Server = $Server
                } `
                -Exception $_.Exception

            # Return empty array on error
            return @()
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Unexpected error retrieving large attribute" `
                -Context @{
                    DN = $DistinguishedName
                    Attribute = $AttributeName
                    Server = $Server
                } `
                -Exception $_.Exception

            throw
        }
    }
}
