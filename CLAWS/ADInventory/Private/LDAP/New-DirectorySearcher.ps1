function New-DirectorySearcher {
    <#
    .SYNOPSIS
        Creates a properly configured DirectorySearcher with timeout and paging settings

    .DESCRIPTION
        Creates a System.DirectoryServices.DirectorySearcher object with proper configuration
        for enterprise AD environments. Includes timeout settings, page size for large result sets,
        and referral chasing configuration.

        IMPORTANT: The returned DirectorySearcher must be disposed by the caller.
        Use try/finally pattern to ensure disposal.

    .PARAMETER DirectoryEntry
        The DirectoryEntry object to search from (required)

    .PARAMETER Filter
        LDAP filter string (e.g., "(objectClass=user)")

    .PARAMETER PropertiesToLoad
        Array of property names to load. Use specific properties instead of loading all
        for better performance.

    .PARAMETER PageSize
        Page size for large result sets (default: 1000)
        Set to 0 to disable paging (not recommended for production)

    .PARAMETER SearchScope
        Search scope: Base, OneLevel, or Subtree (default: Subtree)

    .PARAMETER ServerTimeoutMinutes
        Server-side timeout in minutes (default: 10)
        Server will stop processing after this time

    .PARAMETER ClientTimeoutMinutes
        Client-side timeout in minutes (default: 15)
        Client will stop waiting for results after this time
        Should be >= ServerTimeout

    .PARAMETER ReferralChasing
        Referral chasing behavior: None, Subordinate, All (default: None)
        - None: Don't follow referrals (recommended for FSPs)
        - Subordinate: Follow subordinate referrals only
        - All: Follow all referrals (may cause issues in some topologies)

    .PARAMETER SizeLimit
        Maximum number of objects to return (default: 0 = no limit)

    .OUTPUTS
        System.DirectoryServices.DirectorySearcher
        A configured DirectorySearcher object. CALLER MUST DISPOSE!

    .EXAMPLE
        $de = New-ADConnection -Server "DC01" -Domain "contoso.com"
        try {
            $ds = New-DirectorySearcher -DirectoryEntry $de `
                -Filter "(objectClass=user)" `
                -PropertiesToLoad @('samAccountName', 'mail')
            try {
                $results = $ds.FindAll()
                # Process results
            } finally {
                if ($results) { $results.Dispose() }
                $ds.Dispose()
            }
        } finally {
            $de.Dispose()
        }

    .EXAMPLE
        # Search for Foreign Security Principals with no referral chasing
        $ds = New-DirectorySearcher -DirectoryEntry $de `
            -Filter "(objectClass=foreignSecurityPrincipal)" `
            -SearchScope OneLevel `
            -ReferralChasing None

    .NOTES
        Part of SSNC.ADInventory module

        Connection Leak Prevention:
        - Caller MUST dispose both the DirectorySearcher and SearchResultCollection
        - Use try/finally to ensure disposal even on exceptions

        Improvements over original script:
        - Centralized searcher configuration
        - Timeout configuration (prevents hangs)
        - Consistent paging setup
        - Proper referral chasing configuration
        - Server and client timeouts prevent indefinite hangs
    #>
    [CmdletBinding()]
    [OutputType([System.DirectoryServices.DirectorySearcher])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [string[]]$PropertiesToLoad = @(),

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 5000)]
        [int]$PageSize = 1000,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Base', 'OneLevel', 'Subtree')]
        [string]$SearchScope = 'Subtree',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$ServerTimeoutMinutes = 10,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$ClientTimeoutMinutes = 15,

        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'Subordinate', 'All')]
        [string]$ReferralChasing = 'None',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$SizeLimit = 0
    )

    process {
        Write-ADInventoryLog -Level Verbose -Message "Creating DirectorySearcher" `
            -Context @{
                Filter = $Filter
                PageSize = $PageSize
                SearchScope = $SearchScope
                ServerTimeout = "${ServerTimeoutMinutes}m"
                ClientTimeout = "${ClientTimeoutMinutes}m"
            }

        try {
            # Create searcher
            $ds = New-Object System.DirectoryServices.DirectorySearcher($DirectoryEntry)

            # Set filter and scope
            $ds.Filter = $Filter
            $ds.SearchScope = [System.DirectoryServices.SearchScope]::$SearchScope

            # Configure paging
            $ds.PageSize = $PageSize

            # Configure timeouts (CRITICAL for preventing hangs)
            $ds.ServerTimeLimit = New-TimeSpan -Minutes $ServerTimeoutMinutes
            $ds.ClientTimeout = New-TimeSpan -Minutes $ClientTimeoutMinutes

            # Configure referral chasing
            $ds.ReferralChasing = [System.DirectoryServices.ReferralChasingOption]::$ReferralChasing

            # Set size limit if specified
            if ($SizeLimit -gt 0) {
                $ds.SizeLimit = $SizeLimit
            }

            # Load specific properties if requested
            if ($PropertiesToLoad.Count -gt 0) {
                $ds.PropertiesToLoad.Clear() | Out-Null
                foreach ($prop in $PropertiesToLoad) {
                    [void]$ds.PropertiesToLoad.Add($prop)
                }

                Write-ADInventoryLog -Level Debug -Message "Properties to load configured" `
                    -Context @{
                        PropertyCount = $PropertiesToLoad.Count
                        Properties = ($PropertiesToLoad -join ', ')
                    }
            }

            Write-ADInventoryLog -Level Verbose -Message "DirectorySearcher created successfully"

            return $ds
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to create DirectorySearcher" `
                -Context @{
                    Filter = $Filter
                } `
                -Exception $_.Exception

            # Dispose if partially created
            if ($ds) {
                try { $ds.Dispose() } catch { }
            }

            throw "Failed to create DirectorySearcher: $_"
        }
    }
}
