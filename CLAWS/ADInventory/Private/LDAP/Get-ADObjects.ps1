function Get-ADObjects {
    <#
    .SYNOPSIS
        High-level function to retrieve and transform AD objects

    .DESCRIPTION
        Retrieves AD objects from the specified server and transforms them into
        structured PSCustomObjects with standardized properties. This is a wrapper
        around Get-ADObjectBatch that handles connection creation, property selection,
        and object transformation.

        Returns objects with these properties:
        - SID: Binary SID
        - SID_String: String representation of SID
        - DN: Distinguished Name
        - Name: Object name
        - ObjectClass: Object class (user, group, computer, etc.)
        - Description: Object description (if present)
        - WhenCreated: Creation timestamp
        - WhenChanged: Last modification timestamp
        - Additional properties based on object type

    .PARAMETER Server
        The domain controller to query

    .PARAMETER SearchBase
        The LDAP search base (DN) to start the search from

    .PARAMETER Filter
        LDAP filter string (e.g., "(&(objectCategory=person)(objectClass=user))")

    .PARAMETER Config
        ADQueryConfig object containing connection settings and credentials

    .OUTPUTS
        Array of PSCustomObject with standardized AD object properties

    .EXAMPLE
        $users = Get-ADObjects `
            -Server "10.222.249.89" `
            -SearchBase "DC=contoso,DC=com" `
            -Filter "(&(objectCategory=person)(objectClass=user))" `
            -Config $config

    .NOTES
        Part of SSNC.ADInventory module
        This is the high-level interface used by ADInventorySession
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [ADQueryConfig]$Config = [ADQueryConfig]::new()
    )

    process {
        $de = $null
        $results = [System.Collections.ArrayList]::new()

        try {
            # Create LDAP path
            $ldapPath = "LDAP://$Server/$SearchBase"

            Write-ADInventoryLog -Level Debug -Message "Creating DirectoryEntry" `
                -Context @{
                    Server = $Server
                    SearchBase = $SearchBase
                    Filter = $Filter
                }

            # Create DirectoryEntry
            $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)

            # Apply credentials if provided
            if ($Config.Credential) {
                $de.Username = $Config.Credential.UserName
                $de.Password = $Config.Credential.GetNetworkCredential().Password
            }

            # Extract domain name from search base
            $domainName = ($SearchBase -replace '^.*?DC=', '' -replace ',DC=', '.')

            # Define properties to load based on schema requirements
            $propertiesToLoad = @(
                'objectSid',
                'distinguishedName',
                'name',
                'objectClass',
                'objectGUID',
                'canonicalName',
                'description',
                'whenCreated',
                'whenChanged',
                'samAccountName',
                'displayName',
                'userPrincipalName',
                'mail',
                'givenName',
                'sn',  # surname
                'department',
                'title',
                'manager',
                'employeeID',
                'memberOf',
                'member',
                'primaryGroupID',
                'userAccountControl',
                'groupType',
                'managedBy',
                'sIDHistory',
                'lastLogonTimestamp',
                'pwdLastSet',
                'accountExpires',
                # Computer-specific attributes
                'dNSHostName',
                'operatingSystem',
                'operatingSystemVersion',
                'operatingSystemServicePack',
                'operatingSystemHotfix',
                'isCriticalSystemObject',
                # User-specific attributes
                'employeeNumber',
                'employeeType',
                'msDS-UserPasswordExpired',
                # Security attributes (User & Computer)
                'servicePrincipalName'
            )

            # Define processing script block to transform SearchResult to PSCustomObject
            $processObject = {
                param($result)

                try {
                    # Extract object class and determine object type FIRST
                    # objectClass is multi-valued: (top, person, organizationalPerson, user)
                    # Check if specific classes exist in the array (case-insensitive)
                    $objectClasses = @($result.Properties['objectClass']) | ForEach-Object { "$_".ToLower() }
                    $objectType = if ($objectClasses -contains 'computer') { 3 }
                                  elseif ($objectClasses -contains 'group') { 2 }
                                  elseif ($objectClasses -contains 'user') { 1 }
                                  elseif ($objectClasses -contains 'contact') { 4 }
                                  else { 0 }

                    # Extract SID
                    $sidBytes = $null
                    $sidString = $null
                    if ($result.Properties.Contains('objectSid') -and $result.Properties['objectSid'].Count -gt 0) {
                        $sidBytes = $result.Properties['objectSid'][0]
                        $sidString = ConvertTo-SidString -Value $sidBytes
                    }
                    elseif ($objectType -eq 4) {
                        # Contacts don't have SIDs - they're not security principals
                        # Generate a synthetic identifier using ObjectGUID with "CN:" prefix
                        # This allows contacts to be stored in AD_Object without breaking NOT NULL constraint
                        $objectGuidValue = if ($result.Properties['objectGUID'].Count -gt 0) {
                            ConvertTo-GuidString -Value $result.Properties['objectGUID'][0]
                        } else { $null }

                        # Guard: only create synthetic SID if we have a valid, non-empty GUID
                        # Empty GUID (all zeros) should not produce a synthetic SID
                        $emptyGuid = '00000000-0000-0000-0000-000000000000'
                        if ($objectGuidValue -and $objectGuidValue -ne $emptyGuid) {
                            $sidString = "CN:$objectGuidValue"
                        }
                        else {
                            # Log warning for contacts that cannot get a synthetic SID
                            $dn = if ($result.Properties['distinguishedName'].Count -gt 0) { $result.Properties['distinguishedName'][0] } else { 'unknown' }
                            Write-ADInventoryLog -Level Warning -Message "Contact has no valid objectGUID for synthetic SID: $dn"
                        }
                    }

                    # Extract UserAccountControl and calculate Enabled
                    $uac = if ($result.Properties['userAccountControl'].Count -gt 0) { $result.Properties['userAccountControl'][0] } else { $null }
                    $enabled = if ($null -ne $uac) {
                        # ADS_UF_ACCOUNTDISABLE = 0x0002
                        if (($uac -band 0x0002) -eq 0) { 1 } else { 0 }
                    } else { $null }

                    # Extract GroupType and calculate GroupScope
                    $groupType = if ($result.Properties['groupType'].Count -gt 0) { $result.Properties['groupType'][0] } else { $null }
                    $groupScope = if ($null -ne $groupType) {
                        # Extract scope bits: 0x00000004 = Domain Local, 0x00000002 = Global, 0x00000008 = Universal
                        if (($groupType -band 0x00000004) -ne 0) { 1 }  # Domain Local
                        elseif (($groupType -band 0x00000002) -ne 0) { 2 }  # Global
                        elseif (($groupType -band 0x00000008) -ne 0) { 3 }  # Universal
                        else { 0 }  # Unknown
                    } else { $null }

                    # Extract member DNs for membership processing
                    $memberDNs = if ($result.Properties['member'].Count -gt 0) { @($result.Properties['member']) } else { @() }

                    # Extract SID history
                    $sidHistory = $null
                    if ($result.Properties['sIDHistory'].Count -gt 0) {
                        $sidHistoryArray = @()
                        foreach ($sidBytes in $result.Properties['sIDHistory']) {
                            $histSid = ConvertTo-SidString -Value $sidBytes
                            if ($histSid) { $sidHistoryArray += $histSid }
                        }
                        if ($sidHistoryArray.Count -gt 0) {
                            $sidHistory = ($sidHistoryArray | ConvertTo-Json -Compress)
                        }
                    }

                    # Extract Service Principal Names (multi-valued) - store as JSON array
                    $servicePrincipalName = $null
                    if ($result.Properties['servicePrincipalName'].Count -gt 0) {
                        $spnArray = @($result.Properties['servicePrincipalName'])
                        if ($spnArray.Count -gt 0) {
                            $servicePrincipalName = ($spnArray | ConvertTo-Json -Compress)
                        }
                    }

                    # Extract isCriticalSystemObject (boolean)
                    $isCriticalSystemObject = $null
                    if ($result.Properties['isCriticalSystemObject'].Count -gt 0) {
                        $isCriticalSystemObject = if ($result.Properties['isCriticalSystemObject'][0] -eq $true) { 1 } else { 0 }
                    }

                    # Create object matching AD_Object schema
                    $obj = [PSCustomObject]@{
                        # Identity (NOT NULL in schema)
                        SID = $sidBytes
                        SID_String = $sidString
                        ObjectType = $objectType
                        DomainName = $domainName  # From outer scope
                        DistinguishedName = if ($result.Properties['distinguishedName'].Count -gt 0) { $result.Properties['distinguishedName'][0] } else { $null }

                        # Core Attributes
                        SamAccountName = if ($result.Properties['samAccountName'].Count -gt 0) { $result.Properties['samAccountName'][0] } else { $null }
                        DisplayName = if ($result.Properties['displayName'].Count -gt 0) { $result.Properties['displayName'][0] } else { $null }
                        UserPrincipalName = if ($result.Properties['userPrincipalName'].Count -gt 0) { $result.Properties['userPrincipalName'][0] } else { $null }
                        ObjectGUID = if ($result.Properties['objectGUID'].Count -gt 0) { ConvertTo-GuidString -Value $result.Properties['objectGUID'][0] } else { $null }
                        CanonicalName = if ($result.Properties['canonicalName'].Count -gt 0) { $result.Properties['canonicalName'][0] } else { $null }
                        Description = if ($result.Properties['description'].Count -gt 0) { $result.Properties['description'][0] } else { $null }

                        # Timestamps (use ConvertTo-DateTimeFromAD for Generalized Time format)
                        WhenCreated = ConvertTo-DateTimeFromAD -Value $(if ($result.Properties['whenCreated'].Count -gt 0) { $result.Properties['whenCreated'][0] } else { $null })
                        WhenChanged = ConvertTo-DateTimeFromAD -Value $(if ($result.Properties['whenChanged'].Count -gt 0) { $result.Properties['whenChanged'][0] } else { $null })

                        # Status
                        Enabled = $enabled

                        # Account Security Attributes (Users and Computers only - ObjectType 1 or 3)
                        LastLogonTimestamp = if ($objectType -in @(1, 3)) {
                            ConvertTo-DateTimeFromFileTime -Value $(
                                if ($result.Properties['lastLogonTimestamp'].Count -gt 0) {
                                    $result.Properties['lastLogonTimestamp'][0]
                                } else { $null }
                            )
                        } else { $null }

                        PasswordLastSet = if ($objectType -in @(1, 3)) {
                            ConvertTo-DateTimeFromFileTime -Value $(
                                if ($result.Properties['pwdLastSet'].Count -gt 0) {
                                    $result.Properties['pwdLastSet'][0]
                                } else { $null }
                            )
                        } else { $null }

                        AccountExpires = if ($objectType -in @(1, 3)) {
                            ConvertTo-DateTimeFromFileTime -Value $(
                                if ($result.Properties['accountExpires'].Count -gt 0) {
                                    $result.Properties['accountExpires'][0]
                                } else { $null }
                            )
                        } else { $null }

                        PasswordNeverExpires = if ($objectType -in @(1, 3) -and $null -ne $uac) {
                            # ADS_UF_DONT_EXPIRE_PASSWD = 0x10000 (65536)
                            if (($uac -band 0x10000) -ne 0) { 1 } else { 0 }
                        } else { $null }

                        # User Attributes
                        GivenName = if ($result.Properties['givenName'].Count -gt 0) { $result.Properties['givenName'][0] } else { $null }
                        Surname = if ($result.Properties['sn'].Count -gt 0) { $result.Properties['sn'][0] } else { $null }
                        Mail = if ($result.Properties['mail'].Count -gt 0) { $result.Properties['mail'][0] } else { $null }
                        Department = if ($result.Properties['department'].Count -gt 0) { $result.Properties['department'][0] } else { $null }
                        Title = if ($result.Properties['title'].Count -gt 0) { $result.Properties['title'][0] } else { $null }
                        Manager = if ($result.Properties['manager'].Count -gt 0) { $result.Properties['manager'][0] } else { $null }
                        EmployeeID = if ($result.Properties['employeeID'].Count -gt 0) { $result.Properties['employeeID'][0] } else { $null }
                        EmployeeNumber = if ($result.Properties['employeeNumber'].Count -gt 0) { $result.Properties['employeeNumber'][0] } else { $null }
                        EmployeeType = if ($result.Properties['employeeType'].Count -gt 0) { $result.Properties['employeeType'][0] } else { $null }

                        # Group Attributes
                        GroupType = $groupType
                        GroupScope = $groupScope
                        ManagedBy = if ($result.Properties['managedBy'].Count -gt 0) { $result.Properties['managedBy'][0] } else { $null }

                        # Computer Attributes
                        DNSHostName = if ($objectType -eq 3 -and $result.Properties['dNSHostName'].Count -gt 0) { $result.Properties['dNSHostName'][0] } else { $null }
                        OperatingSystem = if ($objectType -eq 3 -and $result.Properties['operatingSystem'].Count -gt 0) { $result.Properties['operatingSystem'][0] } else { $null }
                        OperatingSystemVersion = if ($objectType -eq 3 -and $result.Properties['operatingSystemVersion'].Count -gt 0) { $result.Properties['operatingSystemVersion'][0] } else { $null }
                        OperatingSystemServicePack = if ($objectType -eq 3 -and $result.Properties['operatingSystemServicePack'].Count -gt 0) { $result.Properties['operatingSystemServicePack'][0] } else { $null }
                        OperatingSystemHotfix = if ($objectType -eq 3 -and $result.Properties['operatingSystemHotfix'].Count -gt 0) { $result.Properties['operatingSystemHotfix'][0] } else { $null }

                        # Security Attributes
                        IsCriticalSystemObject = $isCriticalSystemObject
                        ServicePrincipalName = $servicePrincipalName
                        UserAccountControl = $uac  # Raw bitmask value

                        # Password Expired (computed attribute for users)
                        PasswordExpired = if ($objectType -eq 1 -and $result.Properties['msDS-UserPasswordExpired'].Count -gt 0) {
                            if ($result.Properties['msDS-UserPasswordExpired'][0] -eq $true) { 1 } else { 0 }
                        } else { $null }

                        # Security
                        SIDHistory = $sidHistory

                        # Foreign Security Principal Support
                        IsForeignSecurityPrincipal = 0
                        SourceDomain = $null

                        # Additional properties for membership processing (not in database)
                        Member = $memberDNs
                    }

                    return $obj
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Failed to process search result" `
                        -Exception $_.Exception
                    return $null
                }
            }

            # Call low-level Get-ADObjectBatch with transformation
            $processedObjects = Get-ADObjectBatch `
                -DirectoryEntry $de `
                -Filter $Filter `
                -PropertiesToLoad $propertiesToLoad `
                -PageSize $Config.PageSize `
                -ServerTimeoutMinutes $Config.ServerTimeoutMinutes `
                -ClientTimeoutMinutes $Config.ClientTimeoutMinutes `
                -ProcessObject $processObject `
                -ShowProgress $false

            Write-ADInventoryLog -Level Info -Message "AD objects retrieved" `
                -Context @{
                    Count = $processedObjects.Count
                    Filter = $Filter
                    Server = $Server
                }

            return $processedObjects
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to retrieve AD objects" `
                -Context @{
                    Server = $Server
                    SearchBase = $SearchBase
                    Filter = $Filter
                } `
                -Exception $_.Exception
            throw
        }
        finally {
            if ($de) {
                $de.Dispose()
            }
        }
    }
}
