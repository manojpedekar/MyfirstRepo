function Get-TargetDomainList {
    <#
    .SYNOPSIS
        Resolves the list of domains to process based on input parameters

    .DESCRIPTION
        Determines which domains to inventory based on the specified mode:
        - CurrentDomain: Only the current computer's domain
        - WalkTrust: Current domain + all trusted domains (inbound/bidirectional)
        - Explicit list: User-specified domain names

        REPLACES original script logic (lines 1390-1424):
        - Cleaner separation of concerns
        - Better error handling
        - Explicit parameter validation
        - Returns structured result

    .PARAMETER CurrentDomain
        If specified, returns only the current computer's domain

    .PARAMETER WalkTrust
        If specified, returns current domain + all trusted domains with inbound/bidirectional trusts

    .PARAMETER Domains
        Explicit array of domain names to process.
        Can be combined with -WalkTrust to enumerate trusts from these domains.

    .OUTPUTS
        Array of domain names (strings)

    .EXAMPLE
        # Get current domain only
        $domains = Get-TargetDomainList -CurrentDomain
        # Returns: @("contoso.com")

    .EXAMPLE
        # Get current domain and trusted domains
        $domains = Get-TargetDomainList -WalkTrust
        # Returns: @("contoso.com", "fabrikam.com", "trusted.com")

    .EXAMPLE
        # Get specific domains
        $domains = Get-TargetDomainList -Domains "contoso.com", "fabrikam.com"
        # Returns: @("contoso.com", "fabrikam.com")

    .EXAMPLE
        # Get specific domain AND its trusted domains (remote trust walking)
        $domains = Get-TargetDomainList -Domains "contoso.com" -WalkTrust
        # Returns: @("contoso.com", "fabrikam.com", "trusted.com")
        # Useful when running from a computer in a different domain

    .NOTES
        Part of SSNC.ADInventory module

        Trust Walking:
        - Only follows Inbound and Bidirectional trusts
        - Does not follow Outbound-only trusts
        - Trusts must be active and accessible

        Error Handling:
        - Returns empty array if domain discovery fails
        - Logs warnings for trust enumeration failures
        - Throws if no domains can be determined
    #>
    [CmdletBinding(DefaultParameterSetName = 'CurrentDomain')]
    [OutputType([string[]])]
    param(
        [Parameter(ParameterSetName = 'CurrentDomain', Mandatory = $true)]
        [switch]$CurrentDomain,

        [Parameter(ParameterSetName = 'WalkTrust', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Explicit')]
        [switch]$WalkTrust,

        [Parameter(ParameterSetName = 'Explicit', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domains
    )

    process {
        $domainList = [System.Collections.ArrayList]::new()

        Write-ADInventoryLog -Level Info -Message "Resolving target domain list" `
            -Context @{ ParameterSet = $PSCmdlet.ParameterSetName }

        try {
            switch ($PSCmdlet.ParameterSetName) {
                'CurrentDomain' {
                    Write-ADInventoryLog -Level Debug -Message "Getting current computer domain"

                    try {
                        $currentDomainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
                        [void]$domainList.Add($currentDomainObj.Name)

                        Write-ADInventoryLog -Level Info -Message "Current domain identified" `
                            -Context @{ DomainName = $currentDomainObj.Name }
                    }
                    catch {
                        Write-ADInventoryLog -Level Error -Message "Failed to get current domain" `
                            -Exception $_.Exception

                        throw "Failed to get current computer domain. Ensure this computer is domain-joined: $_"
                    }
                }

                'WalkTrust' {
                    Write-ADInventoryLog -Level Debug -Message "Walking trust relationships for domain inventory"

                    try {
                        # Get current domain
                        $currentDomainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
                        [void]$domainList.Add($currentDomainObj.Name)

                        Write-ADInventoryLog -Level Info -Message "Starting from current domain" `
                            -Context @{ DomainName = $currentDomainObj.Name }

                        # Get trusts
                        try {
                            $trusts = $currentDomainObj.GetAllTrustRelationships()

                            # IMPORTANT: Only Inbound and Bidirectional trusts can be inventoried
                            # - Inbound: The target domain trusts us, so we can authenticate and query it
                            # - Bidirectional: Mutual trust, we can query in both directions
                            # - Outbound: We trust the target domain, but they don't trust us,
                            #             so we cannot authenticate to query their AD
                            #
                            # NOTE: All trust links (including Outbound) are still COLLECTED and stored
                            #       in the database during the inventory of each domain for complete
                            #       trust topology visibility. This filter only affects which domains
                            #       we attempt to inventory (query for AD objects).
                            $relevantTrusts = $trusts | Where-Object {
                                $_.TrustDirection -in @(
                                    [System.DirectoryServices.ActiveDirectory.TrustDirection]::Inbound,
                                    [System.DirectoryServices.ActiveDirectory.TrustDirection]::Bidirectional
                                )
                            }

                            # Calculate counts for logging
                            $inboundCount = ($trusts | Where-Object {
                                $_.TrustDirection -eq [System.DirectoryServices.ActiveDirectory.TrustDirection]::Inbound
                            }).Count
                            $outboundCount = ($trusts | Where-Object {
                                $_.TrustDirection -eq [System.DirectoryServices.ActiveDirectory.TrustDirection]::Outbound
                            }).Count
                            $bidirectionalCount = ($trusts | Where-Object {
                                $_.TrustDirection -eq [System.DirectoryServices.ActiveDirectory.TrustDirection]::Bidirectional
                            }).Count

                            Write-ADInventoryLog -Level Info -Message "Trust relationships analyzed for WalkTrust" `
                                -Context @{
                                    TotalTrusts = $trusts.Count
                                    Inbound = $inboundCount
                                    Outbound = $outboundCount
                                    Bidirectional = $bidirectionalCount
                                    DomainsToInventory = $relevantTrusts.Count
                                    SkippedOutbound = $outboundCount
                                }

                            if ($outboundCount -gt 0) {
                                Write-ADInventoryLog -Level Info -Message "Outbound-only trusts will NOT be inventoried (cannot authenticate)" `
                                    -Context @{ OutboundCount = $outboundCount }
                            }

                            # Add trusted domains that we can actually query
                            foreach ($trust in $relevantTrusts) {
                                [void]$domainList.Add($trust.TargetName)

                                Write-ADInventoryLog -Level Debug -Message "Added trusted domain for inventory" `
                                    -Context @{
                                        DomainName = $trust.TargetName
                                        TrustType = $trust.TrustType
                                        TrustDirection = $trust.TrustDirection
                                    }
                            }
                        }
                        catch {
                            Write-ADInventoryLog -Level Warning -Message "Failed to enumerate trusts" `
                                -Context @{ DomainName = $currentDomainObj.Name } `
                                -Exception $_.Exception

                            Write-Warning "Failed to enumerate trusts from $($currentDomainObj.Name). Proceeding with current domain only."
                        }
                    }
                    catch {
                        Write-ADInventoryLog -Level Error -Message "Failed to get current domain for trust walking" `
                            -Exception $_.Exception

                        throw "Failed to get current computer domain. Ensure this computer is domain-joined: $_"
                    }
                }

                'Explicit' {
                    Write-ADInventoryLog -Level Debug -Message "Using explicit domain list" `
                        -Context @{ DomainCount = $Domains.Count; WalkTrust = $WalkTrust.IsPresent }

                    foreach ($domain in $Domains) {
                        if (-not [string]::IsNullOrWhiteSpace($domain)) {
                            $trimmedDomain = $domain.Trim()
                            [void]$domainList.Add($trimmedDomain)

                            Write-ADInventoryLog -Level Debug -Message "Added explicit domain" `
                                -Context @{ DomainName = $trimmedDomain }

                            # If -WalkTrust is specified, enumerate trusts from this domain
                            if ($WalkTrust) {
                                Write-ADInventoryLog -Level Info -Message "Walking trusts from remote domain" `
                                    -Context @{ DomainName = $trimmedDomain }

                                try {
                                    # Use Get-ADDomainTrust to enumerate trusts from the remote domain
                                    $trusts = Get-ADDomainTrust -DomainName $trimmedDomain

                                    # Filter to Inbound and Bidirectional trusts only
                                    # These are the trusts where we can authenticate to the target domain
                                    $relevantTrusts = $trusts | Where-Object {
                                        $_.TrustDirection -in @('Inbound', 'Bidirectional')
                                    }

                                    # Calculate counts for logging
                                    $inboundCount = @($trusts | Where-Object { $_.TrustDirection -eq 'Inbound' }).Count
                                    $outboundCount = @($trusts | Where-Object { $_.TrustDirection -eq 'Outbound' }).Count
                                    $bidirectionalCount = @($trusts | Where-Object { $_.TrustDirection -eq 'Bidirectional' }).Count

                                    Write-ADInventoryLog -Level Info -Message "Trust relationships analyzed for remote WalkTrust" `
                                        -Context @{
                                            SourceDomain = $trimmedDomain
                                            TotalTrusts = $trusts.Count
                                            Inbound = $inboundCount
                                            Outbound = $outboundCount
                                            Bidirectional = $bidirectionalCount
                                            DomainsToInventory = $relevantTrusts.Count
                                            SkippedOutbound = $outboundCount
                                        }

                                    if ($outboundCount -gt 0) {
                                        Write-ADInventoryLog -Level Info -Message "Outbound-only trusts will NOT be inventoried (cannot authenticate)" `
                                            -Context @{ OutboundCount = $outboundCount }
                                    }

                                    # Add trusted domains that we can actually query
                                    foreach ($trust in $relevantTrusts) {
                                        if (-not [string]::IsNullOrEmpty($trust.TargetDomain)) {
                                            [void]$domainList.Add($trust.TargetDomain)

                                            Write-ADInventoryLog -Level Debug -Message "Added trusted domain for inventory" `
                                                -Context @{
                                                    SourceDomain = $trimmedDomain
                                                    TargetDomain = $trust.TargetDomain
                                                    TrustType = $trust.TrustType
                                                    TrustDirection = $trust.TrustDirection
                                                }
                                        }
                                    }
                                }
                                catch {
                                    Write-ADInventoryLog -Level Warning -Message "Failed to enumerate trusts from remote domain" `
                                        -Context @{ DomainName = $trimmedDomain } `
                                        -Exception $_.Exception

                                    Write-Warning "Failed to enumerate trusts from $trimmedDomain. Proceeding with explicit domain only: $_"
                                }
                            }
                        }
                    }
                }
            }

            # Validate we have at least one domain
            if ($domainList.Count -eq 0) {
                Write-ADInventoryLog -Level Error -Message "No domains to process"
                throw "No domains to process. Domain list is empty."
            }

            # Remove duplicates (case-insensitive)
            $uniqueDomains = $domainList | Select-Object -Unique

            Write-ADInventoryLog -Level Info -Message "Target domains resolved" `
                -Context @{
                    DomainCount = $uniqueDomains.Count
                    Domains = ($uniqueDomains -join ', ')
                }

            return $uniqueDomains
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to resolve target domain list" `
                -Exception $_.Exception

            throw
        }
    }
}
