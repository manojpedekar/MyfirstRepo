function Test-ADConnectivity {
    <#
    .SYNOPSIS
        Tests connectivity to a domain controller on specified port with latency measurement

    .DESCRIPTION
        Tests both port connectivity and network latency to a domain controller.
        Used by Get-OptimalDomainController to find the best DC for queries.

        IMPROVEMENTS over original script (lines 189-205):
        - Better error handling
        - Configurable timeout
        - More reliable latency measurement
        - Supports multiple latency measurement methods

    .PARAMETER ComputerName
        The computer name or IP address to test

    .PARAMETER Port
        The port to test (default: 636 for LDAPS)

    .PARAMETER TimeoutMilliseconds
        Connection timeout in milliseconds (default: 1000)

    .PARAMETER MeasureLatency
        If specified, measures network latency using Test-Connection

    .OUTPUTS
        PSCustomObject with properties:
        - ComputerName: The tested computer
        - IPAddress: Resolved IP address
        - Port: The tested port
        - PortOpen: Boolean indicating if port is accessible
        - Latency: Network latency in milliseconds (if measured)
        - Success: Overall success indicator

    .EXAMPLE
        Test-ADConnectivity -ComputerName "DC01.contoso.com" -Port 636
        Tests LDAPS connectivity to DC01

    .EXAMPLE
        Test-ADConnectivity -ComputerName "10.0.0.1" -MeasureLatency
        Tests connectivity and measures latency

    .NOTES
        Part of SSNC.ADInventory module

        Port Reference:
        - 636: LDAPS (secure LDAP)
        - 389: LDAP (unencrypted)
        - 3268: Global Catalog
        - 3269: Global Catalog LDAPS
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port = 636,

        [Parameter(Mandatory = $false)]
        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 1000,

        [Parameter(Mandatory = $false)]
        [switch]$MeasureLatency
    )

    process {
        Write-ADInventoryLog -Level Debug -Message "Testing connectivity" `
            -Context @{
                ComputerName = $ComputerName
                Port = $Port
                Timeout = "${TimeoutMilliseconds}ms"
            }

        $result = [PSCustomObject]@{
            ComputerName = $ComputerName
            IPAddress = $null
            Port = $Port
            PortOpen = $false
            Latency = $null
            Success = $false
        }

        try {
            # Resolve IP address if hostname provided
            if ($ComputerName -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                $result.IPAddress = $ComputerName
            }
            else {
                try {
                    $resolved = [System.Net.Dns]::GetHostAddresses($ComputerName) |
                                Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                                Select-Object -First 1

                    if ($resolved) {
                        $result.IPAddress = $resolved.IPAddressToString
                    }
                    else {
                        Write-ADInventoryLog -Level Warning -Message "Could not resolve hostname" `
                            -Context @{ ComputerName = $ComputerName }
                        return $result
                    }
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "DNS resolution failed" `
                        -Context @{ ComputerName = $ComputerName } `
                        -Exception $_.Exception
                    return $result
                }
            }

            # Test port connectivity
            $tcpClient = $null
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connectTask = $tcpClient.ConnectAsync($result.IPAddress, $Port)
                $result.PortOpen = $connectTask.Wait($TimeoutMilliseconds)

                Write-ADInventoryLog -Level Debug -Message "Port test completed" `
                    -Context @{
                        IPAddress = $result.IPAddress
                        Port = $Port
                        PortOpen = $result.PortOpen
                    }
            }
            catch {
                Write-ADInventoryLog -Level Debug -Message "Port test failed" `
                    -Context @{
                        IPAddress = $result.IPAddress
                        Port = $Port
                    } `
                    -Exception $_.Exception

                $result.PortOpen = $false
            }
            finally {
                if ($tcpClient) {
                    try { $tcpClient.Close(); $tcpClient.Dispose() } catch { }
                }
            }

            # Measure latency if requested and port is open
            if ($MeasureLatency -and $result.PortOpen) {
                try {
                    $ping = Test-Connection -ComputerName $result.IPAddress -Count 1 -ErrorAction Stop | Select-Object -First 1

                    # Try different property names (varies by PowerShell version)
                    $latencyProperties = @('ResponseTime', 'Latency', 'RoundtripTime')
                    foreach ($propName in $latencyProperties) {
                        if ($ping.PSObject.Properties.Match($propName).Count -gt 0) {
                            $result.Latency = [double]$ping.$propName
                            break
                        }
                    }

                    Write-ADInventoryLog -Level Debug -Message "Latency measured" `
                        -Context @{
                            IPAddress = $result.IPAddress
                            Latency = "$($result.Latency)ms"
                        }
                }
                catch {
                    Write-ADInventoryLog -Level Debug -Message "Latency measurement failed" `
                        -Context @{ IPAddress = $result.IPAddress } `
                        -Exception $_.Exception

                    $result.Latency = 99999  # High value to deprioritize
                }
            }
            elseif ($MeasureLatency) {
                # Port not open, set high latency
                $result.Latency = 99999
            }

            $result.Success = $result.PortOpen

            return $result
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Connectivity test failed" `
                -Context @{
                    ComputerName = $ComputerName
                    Port = $Port
                } `
                -Exception $_.Exception

            return $result
        }
    }
}
