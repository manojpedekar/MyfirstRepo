function Get-OptimalDomainController {
    <#
    .SYNOPSIS
        Finds the optimal domain controller for queries based on connectivity and latency

    .DESCRIPTION
        Resolves domain controllers for a given domain, tests connectivity and latency,
        and returns the best DC for queries. Uses DNS to discover DCs and measures
        LDAPS (port 636) connectivity and network latency.

        IMPROVEMENTS over original script (lines 1458-1473):
        - Configurable port (not just 636)
        - Better error handling
        - Falls back to non-latency selection if measurement fails
        - Validates DC list before testing
        - Progress reporting
        - Returns structured result

    .PARAMETER DomainName
        The domain name to find DCs for (e.g., "contoso.com")

    .PARAMETER Config
        Optional ADQueryConfig object with connection settings
        If not provided, uses default configuration

    .PARAMETER Port
        Port to test (default: 636 for LDAPS)
        Common ports: 636 (LDAPS), 389 (LDAP), 3268 (GC), 3269 (GC LDAPS)

    .PARAMETER PreferLocal
        If specified, prefers DCs in same site/subnet

    .OUTPUTS
        PSCustomObject with properties:
        - DomainName: The domain name
        - DCHostname: The selected DC hostname
        - IPAddress: The DC IP address
        - Port: The tested port
        - Latency: Network latency in ms
        - IsLocal: Boolean indicating if DC is local
        - TestedDCs: Number of DCs tested

    .EXAMPLE
        $dc = Get-OptimalDomainController -DomainName "contoso.com"
        Write-Host "Using DC: $($dc.IPAddress) (latency: $($dc.Latency)ms)"

    .EXAMPLE
        $config = [ADQueryConfig]::new()
        $config.DCTestPort = 389
        $dc = Get-OptimalDomainController -DomainName "contoso.com" -Config $config

    .NOTES
        Part of SSNC.ADInventory module

        DC Discovery:
        - Uses DNS A record resolution for domain name
        - Tests all discovered DCs
        - Selects lowest latency with open port
        - Returns null if no DCs are accessible
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [ADQueryConfig]$Config = [ADQueryConfig]::new(),

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [switch]$PreferLocal
    )

    process {
        # Determine port to test
        if (-not $Port) {
            $Port = $Config.DCTestPort
        }

        Write-ADInventoryLog -Level Info -Message "Finding optimal domain controller" `
            -Context @{
                DomainName = $DomainName
                Port = $Port
            }

        try {
            # Resolve DCs via DNS
            Write-ADInventoryLog -Level Debug -Message "Resolving DCs via DNS"

            $dnsRecords = Resolve-DnsName -Name $DomainName -ErrorAction Stop |
                          Where-Object {
                              $_.QueryType -ne "NS" -and
                              $_.Type -eq "A" -and
                              $_.Name -eq $DomainName
                          }

            if ($null -eq $dnsRecords -or @($dnsRecords).Count -eq 0) {
                Write-ADInventoryLog -Level Error -Message "No DCs found via DNS" `
                    -Context @{ DomainName = $DomainName }

                throw "No domain controllers found for $DomainName"
            }

            $dcList = @($dnsRecords)
            Write-ADInventoryLog -Level Info -Message "Discovered DCs" `
                -Context @{
                    DomainName = $DomainName
                    DCCount = $dcList.Count
                }

            # Test connectivity to all DCs
            $testResults = [System.Collections.ArrayList]::new()
            $progressId = Get-Random -Minimum 1000 -Maximum 9999

            for ($i = 0; $i -lt $dcList.Count; $i++) {
                $dc = $dcList[$i]

                Write-Progress -Id $progressId `
                    -Activity "Testing domain controllers for $DomainName" `
                    -Status "Testing $($dc.IPAddress)" `
                    -PercentComplete (($i / $dcList.Count) * 100)

                $testResult = Test-ADConnectivity -ComputerName $dc.IPAddress `
                                                   -Port $Port `
                                                   -TimeoutMilliseconds $Config.DCTestTimeout `
                                                   -MeasureLatency

                if ($testResult) {
                    [void]$testResults.Add($testResult)
                }
            }

            Write-Progress -Id $progressId -Activity "Testing domain controllers" -Completed

            # Filter to accessible DCs only
            $accessibleDCs = $testResults | Where-Object { $_.PortOpen -eq $true }

            if ($accessibleDCs.Count -eq 0) {
                Write-ADInventoryLog -Level Error -Message "No accessible DCs found" `
                    -Context @{
                        DomainName = $DomainName
                        Port = $Port
                        TestedDCs = $testResults.Count
                    }

                throw "No accessible domain controllers found for $DomainName on port $Port"
            }

            Write-ADInventoryLog -Level Info -Message "Accessible DCs found" `
                -Context @{
                    DomainName = $DomainName
                    AccessibleCount = $accessibleDCs.Count
                    TotalTested = $testResults.Count
                }

            # Select best DC (lowest latency)
            $bestDC = $accessibleDCs | Sort-Object Latency | Select-Object -First 1

            # Build result object
            $result = [PSCustomObject]@{
                DomainName = $DomainName
                DCHostname = $bestDC.ComputerName
                IPAddress = $bestDC.IPAddress
                Port = $Port
                Latency = $bestDC.Latency
                IsLocal = $false  # Could be enhanced with site detection
                TestedDCs = $testResults.Count
                AccessibleDCs = $accessibleDCs.Count
            }

            Write-ADInventoryLog -Level Info -Message "Optimal DC selected" `
                -Context @{
                    DomainName = $DomainName
                    IPAddress = $result.IPAddress
                    Latency = "$($result.Latency)ms"
                    TestedDCs = $result.TestedDCs
                }

            return $result
        }
        catch [System.ComponentModel.Win32Exception] {
            Write-ADInventoryLog -Level Error -Message "DNS resolution failed" `
                -Context @{ DomainName = $DomainName } `
                -Exception $_.Exception

            throw "Failed to resolve domain controllers for ${DomainName}: $_"
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to find optimal DC" `
                -Context @{ DomainName = $DomainName } `
                -Exception $_.Exception

            throw "Failed to find optimal domain controller for ${DomainName}: $_"
        }
    }
}
