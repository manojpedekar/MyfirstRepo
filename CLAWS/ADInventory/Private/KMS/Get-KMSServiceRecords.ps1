<#
.SYNOPSIS
    Collects KMS (Key Management Service) server records via DNS SRV queries.

.DESCRIPTION
    Queries DNS for KMS service records using the standard SRV record format:
    _vlmcs._tcp.{domain}

    KMS hosts register SRV records in DNS to allow clients to locate activation
    services. This function discovers these records and optionally resolves
    the target hostnames to IP addresses.

    Note: Many domains do not have KMS servers or use cloud activation instead.
    This function handles missing records gracefully.

.PARAMETER DomainName
    The domain name to query for KMS SRV records.

.PARAMETER ResolveIP
    If specified, attempts to resolve each KMS target hostname to an IP address.

.PARAMETER Config
    Optional ADQueryConfig object with query settings (unused in DNS queries but
    included for consistency with other collection functions).

.OUTPUTS
    Array of PSCustomObject with the following properties:
    - DomainName: The domain queried
    - TargetHostname: The KMS server hostname from SRV record
    - Port: The KMS service port (typically 1688)
    - Priority: SRV record priority
    - Weight: SRV record weight
    - TTL: Time-to-live of the DNS record
    - ResolvedIP: IP address if -ResolveIP was specified, otherwise null
    - RecordSource: Always 'DNS' for this function

.NOTES
    Part of SSNC.ADInventory module
    Domain-scoped data - collect once per domain

    DNS SRV Record Format:
    _vlmcs._tcp.domain.com SRV priority weight port target

    Common scenarios:
    - No KMS servers: Returns empty array (common for cloud-activated environments)
    - Multiple KMS servers: Returns all discovered servers
    - KMS server unreachable: Still returns DNS record (IP resolution may fail)

.EXAMPLE
    Get-KMSServiceRecords -DomainName "contoso.com"
    Returns all KMS SRV records for contoso.com without IP resolution.

.EXAMPLE
    Get-KMSServiceRecords -DomainName "contoso.com" -ResolveIP
    Returns all KMS SRV records with resolved IP addresses.
#>
function Get-KMSServiceRecords {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [switch]$ResolveIP,

        [Parameter(Mandatory = $false)]
        [ADQueryConfig]$Config
    )

    process {
        $kmsRecords = [System.Collections.ArrayList]::new()

        Write-ADInventoryLog -Level Info -Message "Querying KMS service records" `
            -Category Collection `
            -Context @{
                DomainName = $DomainName
                ResolveIP = $ResolveIP.IsPresent
            }

        try {
            # Build the SRV record query name
            $srvQuery = "_vlmcs._tcp.$DomainName"

            Write-ADInventoryLog -Level Debug -Message "DNS SRV query" `
                -Context @{ Query = $srvQuery }

            # Query DNS for KMS SRV records
            $dnsResults = $null
            try {
                $dnsResults = Resolve-DnsName -Name $srvQuery -Type SRV -DnsOnly -ErrorAction Stop
            }
            catch [System.ComponentModel.Win32Exception] {
                # DNS_INFO_NO_RECORDS (9501) or similar - no KMS records exist
                Write-ADInventoryLog -Level Info -Message "No KMS SRV records found for domain" `
                    -Context @{ DomainName = $DomainName; Query = $srvQuery }
                return @()
            }
            catch {
                # Other DNS errors (network issues, DNS server unavailable, etc.)
                Write-ADInventoryLog -Level Warning -Message "DNS query failed for KMS records" `
                    -Context @{ DomainName = $DomainName; Query = $srvQuery } `
                    -Exception $_.Exception
                return @()
            }

            # Filter for SRV records only (Resolve-DnsName may return additional records)
            $srvRecords = $dnsResults | Where-Object { $_.Type -eq 'SRV' }

            if (-not $srvRecords -or $srvRecords.Count -eq 0) {
                Write-ADInventoryLog -Level Info -Message "No KMS SRV records found for domain" `
                    -Context @{ DomainName = $DomainName }
                return @()
            }

            foreach ($srv in $srvRecords) {
                $resolvedIP = $null

                # Optionally resolve the target hostname to IP
                if ($ResolveIP.IsPresent -and $srv.NameTarget) {
                    try {
                        $ipResult = Resolve-DnsName -Name $srv.NameTarget -Type A -DnsOnly -ErrorAction Stop |
                            Where-Object { $_.Type -eq 'A' } |
                            Select-Object -First 1

                        if ($ipResult) {
                            $resolvedIP = $ipResult.IPAddress
                        }
                    }
                    catch {
                        Write-ADInventoryLog -Level Debug -Message "Could not resolve KMS target hostname" `
                            -Context @{ Target = $srv.NameTarget }
                    }
                }

                $record = [PSCustomObject]@{
                    DomainName     = $DomainName
                    TargetHostname = $srv.NameTarget
                    Port           = $srv.Port
                    Priority       = $srv.Priority
                    Weight         = $srv.Weight
                    TTL            = $srv.TTL
                    ResolvedIP     = $resolvedIP
                    RecordSource   = 'DNS'
                }

                [void]$kmsRecords.Add($record)
            }

            Write-ADInventoryLog -Level Info -Message "KMS service records collected" `
                -Category Collection `
                -Context @{
                    DomainName = $DomainName
                    RecordCount = $kmsRecords.Count
                }

            return @($kmsRecords)
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to collect KMS service records" `
                -Category Collection `
                -Context @{ DomainName = $DomainName } `
                -Exception $_.Exception
            return @()
        }
    }
}
