<#
.SYNOPSIS
    Collects AD Certificate Services (PKI) information from Active Directory.

.DESCRIPTION
    Queries the Configuration partition for Active Directory Certificate Services
    (AD CS) configuration including:
    - Enterprise Certification Authorities (pKIEnrollmentService)
    - Certificate Templates (pKICertificateTemplate)
    - Trusted Root CAs (certificationAuthority in Certification Authorities container)
    - NTAuth Certificates (for smart card authentication)

    This provides visibility into the PKI infrastructure registered in AD.

.PARAMETER Server
    IP address or hostname of a domain controller to query.

.PARAMETER ForestName
    The forest name (DNS root domain name).

.PARAMETER Config
    Optional ADQueryConfig object with query settings.

.OUTPUTS
    PSCustomObject with the following properties:
    - EnterpriseCAs: Array of Enterprise CA objects
    - CertificateTemplates: Array of certificate template objects
    - TrustedRootCAs: Array of trusted root CA objects
    - NTAuthCAs: Array of NTAuth certificate objects

.NOTES
    Part of SSNC.ADInventory module
    Forest-scoped data - collect once per forest

    LDAP Locations (all under CN=Public Key Services,CN=Services,CN=Configuration):
    - Enterprise CAs: CN=Enrollment Services
    - Certificate Templates: CN=Certificate Templates
    - Trusted Root CAs: CN=Certification Authorities
    - NTAuth Certificates: CN=NTAuthCertificates

    Certificate data is stored as Base64-encoded strings for portability.

.EXAMPLE
    $pkiInfo = Get-ADPKIInfo -Server "dc01.contoso.com" -ForestName "contoso.com"
    $pkiInfo.EnterpriseCAs | Format-Table CAName, DNSHostName
#>
function Get-ADPKIInfo {
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
        Write-ADInventoryLog -Level Info -Message "Collecting PKI information" `
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

            $pkiContainer = "CN=Public Key Services,CN=Services,$configDn"

            # Collect all PKI data types
            $enterpriseCAs = @(Get-ADEnterpriseCAsInternal -Server $Server -PKIContainer $pkiContainer -Config $Config -ForestName $ForestName)
            $certTemplates = @(Get-ADCertificateTemplatesInternal -Server $Server -PKIContainer $pkiContainer -Config $Config -ForestName $ForestName)
            $trustedRootCAs = @(Get-ADTrustedRootCAsInternal -Server $Server -PKIContainer $pkiContainer -Config $Config -ForestName $ForestName)
            $ntAuthCAs = @(Get-ADNTAuthCAsInternal -Server $Server -PKIContainer $pkiContainer -Config $Config -ForestName $ForestName)

            $result = [PSCustomObject]@{
                EnterpriseCAs        = $enterpriseCAs
                CertificateTemplates = $certTemplates
                TrustedRootCAs       = $trustedRootCAs
                NTAuthCAs            = $ntAuthCAs
            }

            Write-ADInventoryLog -Level Info -Message "PKI information collection completed" `
                -Category Collection `
                -Context @{
                    ForestName = $ForestName
                    EnterpriseCAs = $enterpriseCAs.Count
                    CertificateTemplates = $certTemplates.Count
                    TrustedRootCAs = $trustedRootCAs.Count
                    NTAuthCAs = $ntAuthCAs.Count
                }

            return $result
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to collect PKI information" `
                -Category Collection `
                -Context @{ Server = $Server; ForestName = $ForestName } `
                -Exception $_.Exception

            return [PSCustomObject]@{
                EnterpriseCAs        = @()
                CertificateTemplates = @()
                TrustedRootCAs       = @()
                NTAuthCAs            = @()
            }
        }
    }
}

#region Internal Helper Functions

function Get-ADEnterpriseCAsInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$PKIContainer,
        [ADQueryConfig]$Config,
        [string]$ForestName
    )

    $results = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $enrollmentServices = "CN=Enrollment Services,$PKIContainer"

        try {
            $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$enrollmentServices")
            $null = $searchRoot.distinguishedName
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "Enrollment Services container not found" `
                -Context @{ Server = $Server }
            return @()
        }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=pKIEnrollmentService)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'dNSHostName', 'cACertificate', 'cACertificateDN',
            'certificateTemplates', 'flags', 'distinguishedName',
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

            # Convert certificate to Base64
            $certBase64 = $null
            $certDN = $null
            if ($props['cacertificate'] -and $props['cacertificate'].Count -gt 0) {
                $certBytes = $props['cacertificate'][0]
                if ($certBytes -is [byte[]]) {
                    $certBase64 = [Convert]::ToBase64String($certBytes)
                    # Try to parse certificate subject
                    try {
                        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
                        $certDN = $cert.Subject
                        $cert.Dispose()
                    }
                    catch {
                        # Certificate parsing failed - leave subject as null
                    }
                }
            }

            # Get certificate templates as JSON array
            $templates = @()
            if ($props['certificatetemplates'] -and $props['certificatetemplates'].Count -gt 0) {
                $templates = @($props['certificatetemplates'])
            }

            $flags = $null
            if ($props['flags'] -and $props['flags'].Count -gt 0) {
                $flags = [int]$props['flags'][0]
            }

            $record = [PSCustomObject]@{
                ForestName           = $ForestName
                CAName               = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                DNSHostName          = if ($props['dnshostname'] -and $props['dnshostname'].Count -gt 0) { [string]$props['dnshostname'][0] } else { $null }
                CAType               = 'Enterprise'
                CACertificate        = $certBase64
                CACertificateDN      = $certDN
                CertificateTemplates = ($templates | ConvertTo-Json -Compress)
                Flags                = $flags
                DistinguishedName    = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID           = $objectGuid
                WhenCreated          = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged          = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }

            [void]$results.Add($record)
        }

        Write-ADInventoryLog -Level Debug -Message "Enterprise CAs query completed" `
            -Context @{ Server = $Server; CACount = $results.Count }

        return $results.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query Enterprise CAs" `
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

function Get-ADCertificateTemplatesInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$PKIContainer,
        [ADQueryConfig]$Config,
        [string]$ForestName
    )

    $results = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $templatesContainer = "CN=Certificate Templates,$PKIContainer"

        try {
            $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$templatesContainer")
            $null = $searchRoot.distinguishedName
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "Certificate Templates container not found" `
                -Context @{ Server = $Server }
            return @()
        }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=pKICertificateTemplate)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'displayName', 'msPKI-Cert-Template-OID',
            'msPKI-Template-Schema-Version', 'msPKI-Template-Minor-Revision', 'revision',
            'msPKI-RA-Signature', 'msPKI-Minimal-Key-Size',
            'msPKI-Enrollment-Flag', 'msPKI-Private-Key-Flag', 'msPKI-Certificate-Name-Flag',
            'pKIExpirationPeriod', 'pKIOverlapPeriod', 'pKIExtendedKeyUsage',
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

            # Parse validity period (pKIExpirationPeriod)
            $validityPeriod = $null
            if ($props['pkiexpirationperiod'] -and $props['pkiexpirationperiod'].Count -gt 0) {
                $validityPeriod = ConvertFrom-PKIPeriod -PeriodBytes $props['pkiexpirationperiod'][0]
            }

            # Parse renewal period (pKIOverlapPeriod)
            $renewalPeriod = $null
            if ($props['pkioverlapperiod'] -and $props['pkioverlapperiod'].Count -gt 0) {
                $renewalPeriod = ConvertFrom-PKIPeriod -PeriodBytes $props['pkioverlapperiod'][0]
            }

            # Get EKU OIDs as JSON array
            $ekuOids = @()
            if ($props['pkiextendedkeyusage'] -and $props['pkiextendedkeyusage'].Count -gt 0) {
                $ekuOids = @($props['pkiextendedkeyusage'])
            }

            $record = [PSCustomObject]@{
                ForestName           = $ForestName
                TemplateName         = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                DisplayName          = if ($props['displayname'] -and $props['displayname'].Count -gt 0) { [string]$props['displayname'][0] } else { $null }
                TemplateOID          = if ($props['mspki-cert-template-oid'] -and $props['mspki-cert-template-oid'].Count -gt 0) { [string]$props['mspki-cert-template-oid'][0] } else { $null }
                SchemaVersion        = if ($props['mspki-template-schema-version'] -and $props['mspki-template-schema-version'].Count -gt 0) { [int]$props['mspki-template-schema-version'][0] } else { $null }
                MinorRevision        = if ($props['mspki-template-minor-revision'] -and $props['mspki-template-minor-revision'].Count -gt 0) { [int]$props['mspki-template-minor-revision'][0] } else { $null }
                MajorRevision        = if ($props['revision'] -and $props['revision'].Count -gt 0) { [int]$props['revision'][0] } else { $null }
                RASignaturesRequired = if ($props['mspki-ra-signature'] -and $props['mspki-ra-signature'].Count -gt 0) { [int]$props['mspki-ra-signature'][0] } else { $null }
                MinKeySize           = if ($props['mspki-minimal-key-size'] -and $props['mspki-minimal-key-size'].Count -gt 0) { [int]$props['mspki-minimal-key-size'][0] } else { $null }
                EnrollmentFlags      = if ($props['mspki-enrollment-flag'] -and $props['mspki-enrollment-flag'].Count -gt 0) { [int]$props['mspki-enrollment-flag'][0] } else { $null }
                PrivateKeyFlags      = if ($props['mspki-private-key-flag'] -and $props['mspki-private-key-flag'].Count -gt 0) { [int]$props['mspki-private-key-flag'][0] } else { $null }
                CertificateNameFlags = if ($props['mspki-certificate-name-flag'] -and $props['mspki-certificate-name-flag'].Count -gt 0) { [int]$props['mspki-certificate-name-flag'][0] } else { $null }
                ValidityPeriod       = $validityPeriod
                RenewalPeriod        = $renewalPeriod
                ExtendedKeyUsage     = ($ekuOids | ConvertTo-Json -Compress)
                DistinguishedName    = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID           = $objectGuid
                WhenCreated          = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged          = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }

            [void]$results.Add($record)
        }

        Write-ADInventoryLog -Level Debug -Message "Certificate Templates query completed" `
            -Context @{ Server = $Server; TemplateCount = $results.Count }

        return $results.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query Certificate Templates" `
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

function Get-ADTrustedRootCAsInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$PKIContainer,
        [ADQueryConfig]$Config,
        [string]$ForestName
    )

    $results = [System.Collections.ArrayList]::new()

    # Query Certification Authorities container
    $caResults = Get-TrustedCAsFromContainer -Server $Server -PKIContainer $PKIContainer -Config $Config -ForestName $ForestName -ContainerName "Certification Authorities" -ContainerType "CertificationAuthorities"
    foreach ($item in $caResults) { [void]$results.Add($item) }

    # Query AIA container
    $aiaResults = Get-TrustedCAsFromContainer -Server $Server -PKIContainer $PKIContainer -Config $Config -ForestName $ForestName -ContainerName "AIA" -ContainerType "AIA"
    foreach ($item in $aiaResults) { [void]$results.Add($item) }

    # Query CDP container (CRL Distribution Points)
    $cdpResults = Get-TrustedCAsFromContainer -Server $Server -PKIContainer $PKIContainer -Config $Config -ForestName $ForestName -ContainerName "CDP" -ContainerType "CDP"
    foreach ($item in $cdpResults) { [void]$results.Add($item) }

    Write-ADInventoryLog -Level Debug -Message "Trusted Root CAs query completed" `
        -Context @{ Server = $Server; TotalCount = $results.Count }

    return $results.ToArray()
}

function Get-TrustedCAsFromContainer {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$PKIContainer,
        [ADQueryConfig]$Config,
        [string]$ForestName,
        [string]$ContainerName,
        [string]$ContainerType
    )

    $results = [System.Collections.ArrayList]::new()
    $searchRoot = $null
    $searcher = $null
    $searchResults = $null

    try {
        $container = "CN=$ContainerName,$PKIContainer"

        try {
            $searchRoot = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$container")
            $null = $searchRoot.distinguishedName
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "$ContainerName container not found" `
                -Context @{ Server = $Server }
            return @()
        }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
        $searcher.Filter = "(objectClass=certificationAuthority)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PageSize = $Config.PageSize

        $propertiesToLoad = @(
            'cn', 'cACertificate', 'distinguishedName',
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

            # Process certificate
            $certBase64 = $null
            $certSubject = $null
            $certThumbprint = $null
            $certNotBefore = $null
            $certNotAfter = $null

            if ($props['cacertificate'] -and $props['cacertificate'].Count -gt 0) {
                $certBytes = $props['cacertificate'][0]
                if ($certBytes -is [byte[]]) {
                    $certBase64 = [Convert]::ToBase64String($certBytes)
                    try {
                        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
                        $certSubject = $cert.Subject
                        $certThumbprint = $cert.Thumbprint
                        $certNotBefore = $cert.NotBefore.ToUniversalTime().ToString('o')
                        $certNotAfter = $cert.NotAfter.ToUniversalTime().ToString('o')
                        $cert.Dispose()
                    }
                    catch {
                        # Certificate parsing failed
                    }
                }
            }

            $record = [PSCustomObject]@{
                ForestName            = $ForestName
                CAName                = if ($props['cn'] -and $props['cn'].Count -gt 0) { [string]$props['cn'][0] } else { $null }
                CACertificate         = $certBase64
                CertificateSubject    = $certSubject
                CertificateThumbprint = $certThumbprint
                CertificateNotBefore  = $certNotBefore
                CertificateNotAfter   = $certNotAfter
                ContainerType         = $ContainerType
                DistinguishedName     = if ($props['distinguishedname'] -and $props['distinguishedname'].Count -gt 0) { [string]$props['distinguishedname'][0] } else { $null }
                ObjectGUID            = $objectGuid
                WhenCreated           = if ($props['whencreated'] -and $props['whencreated'].Count -gt 0) { [DateTime]$props['whencreated'][0] } else { $null }
                WhenChanged           = if ($props['whenchanged'] -and $props['whenchanged'].Count -gt 0) { [DateTime]$props['whenchanged'][0] } else { $null }
            }

            [void]$results.Add($record)
        }

        return $results.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query $ContainerName container" `
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

function Get-ADNTAuthCAsInternal {
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$PKIContainer,
        [ADQueryConfig]$Config,
        [string]$ForestName
    )

    $results = [System.Collections.ArrayList]::new()
    $entry = $null

    try {
        $ntAuthDn = "CN=NTAuthCertificates,$PKIContainer"

        try {
            $entry = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$Server/$ntAuthDn")
            $null = $entry.distinguishedName
        }
        catch {
            Write-ADInventoryLog -Level Debug -Message "NTAuthCertificates container not found" `
                -Context @{ Server = $Server }
            return @()
        }

        # NTAuthCertificates stores multiple certs in cACertificate attribute
        $certs = $entry.Properties['cACertificate']
        $dn = [string]$entry.Properties['distinguishedName'][0]

        if ($certs -and $certs.Count -gt 0) {
            $index = 0
            foreach ($certBytes in $certs) {
                if ($certBytes -is [byte[]]) {
                    $certBase64 = [Convert]::ToBase64String($certBytes)
                    $certSubject = $null
                    $certThumbprint = $null
                    $certNotBefore = $null
                    $certNotAfter = $null

                    try {
                        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
                        $certSubject = $cert.Subject
                        $certThumbprint = $cert.Thumbprint
                        $certNotBefore = $cert.NotBefore.ToUniversalTime().ToString('o')
                        $certNotAfter = $cert.NotAfter.ToUniversalTime().ToString('o')
                        $cert.Dispose()
                    }
                    catch {
                        # Certificate parsing failed
                        $certSubject = "Unknown (parse error)"
                    }

                    $record = [PSCustomObject]@{
                        ForestName            = $ForestName
                        CertificateSubject    = $certSubject
                        CACertificate         = $certBase64
                        CertificateThumbprint = $certThumbprint
                        CertificateNotBefore  = $certNotBefore
                        CertificateNotAfter   = $certNotAfter
                        CertificateIndex      = $index
                        DistinguishedName     = $dn
                    }

                    [void]$results.Add($record)
                    $index++
                }
            }
        }

        Write-ADInventoryLog -Level Debug -Message "NTAuth CAs query completed" `
            -Context @{ Server = $Server; CertCount = $results.Count }

        return $results.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query NTAuth certificates" `
            -Context @{ Server = $Server } `
            -Exception $_.Exception
        return @()
    }
    finally {
        if ($entry) { try { $entry.Dispose() } catch { } }
    }
}

function ConvertFrom-PKIPeriod {
    <#
    .SYNOPSIS
        Converts pKIExpirationPeriod or pKIOverlapPeriod binary format to readable string.

    .DESCRIPTION
        These attributes store time periods as 8-byte FILETIME intervals (negative).
        The value represents 100-nanosecond intervals.

    .PARAMETER PeriodBytes
        The binary period value from AD.

    .OUTPUTS
        String representation like "2 Years", "6 Weeks", "1 Day".
    #>
    [CmdletBinding()]
    param(
        [byte[]]$PeriodBytes
    )

    if ($null -eq $PeriodBytes -or $PeriodBytes.Length -lt 8) {
        return $null
    }

    try {
        # Convert to Int64 (little-endian)
        $int64Value = [BitConverter]::ToInt64($PeriodBytes, 0)

        # Value is negative (time interval)
        $positiveValue = -$int64Value

        # Convert from 100-nanosecond intervals to days
        $days = $positiveValue / 864000000000

        if ($days -ge 365) {
            $years = [math]::Round($days / 365, 0)
            if ($years -eq 1) { return "1 Year" }
            return "$years Years"
        }
        elseif ($days -ge 30) {
            $months = [math]::Round($days / 30, 0)
            if ($months -eq 1) { return "1 Month" }
            return "$months Months"
        }
        elseif ($days -ge 7) {
            $weeks = [math]::Round($days / 7, 0)
            if ($weeks -eq 1) { return "1 Week" }
            return "$weeks Weeks"
        }
        elseif ($days -ge 1) {
            $roundedDays = [math]::Round($days, 0)
            if ($roundedDays -eq 1) { return "1 Day" }
            return "$roundedDays Days"
        }
        else {
            $hours = [math]::Round($days * 24, 0)
            if ($hours -eq 1) { return "1 Hour" }
            return "$hours Hours"
        }
    }
    catch {
        return $null
    }
}

#endregion
