function Test-ADDomainConnectivity {
    <#
    .SYNOPSIS
        Tests LDAP connectivity to Active Directory domains

    .DESCRIPTION
        Tests domain controller connectivity for one or more AD domains before running
        a full inventory collection. This allows quick validation of network access,
        DNS resolution, and DC availability.

        Uses the same domain resolution logic as Start-ADInventoryCollection, including
        support for remote trust walking.

    .PARAMETER CurrentDomain
        Test connectivity to current computer's domain only

    .PARAMETER WalkTrust
        Test connectivity to current domain and all trusted domains (inbound/bidirectional).
        Can be combined with -Domains to walk trusts starting from a specified remote domain.

    .PARAMETER Domains
        Explicit array of domain names to test.
        When combined with -WalkTrust, trusts will be enumerated from each specified domain.

    .PARAMETER Port
        One or more ports to test (default: 636 for LDAPS)
        Each port must be in valid TCP range (1-65535)
        Common ports: 636 (LDAPS), 389 (LDAP), 3268 (GC), 3269 (GC LDAPS)
        When multiple ports are specified, each DC is tested on all ports.

    .PARAMETER LogFile
        Optional path to write detailed results to a log file

    .PARAMETER OutCliXml
        Optional path to export results as CliXml for later analysis.
        Exports a structured object containing:
        - Summary: Test metadata, ports tested, overall pass/fail counts
        - SourceInfo: Source computer name, IPs, user, domain
        - DomainSummary: Per-domain/port results (Domain, Status, BestDC, Port, PortDesc, Total, Pass, Fail)
        - DCInfo: Individual DC test results (Domain, DCIpAddress, Port, PortDesc, Status, Latency)
        Useful for firewall rule planning and subnet/routing analysis.

    .PARAMETER Quiet
        Suppress console output, only return result objects

    .OUTPUTS
        Array of PSCustomObject with connectivity results for each domain

    .EXAMPLE
        Test-ADDomainConnectivity -CurrentDomain
        Tests connectivity to current domain

    .EXAMPLE
        Test-ADDomainConnectivity -Domains "admgmt.ssncad.global" -WalkTrust
        Tests connectivity to the specified domain and all its trusted domains

    .EXAMPLE
        $params = @{
            Domains   = 'admgmt.ssncad.global'
            WalkTrust = $true
            LogFile   = 'C:\temp\connectivity-test.log'
        }
        Test-ADDomainConnectivity @params
        Tests connectivity and writes detailed results to log file

    .EXAMPLE
        $params = @{
            Domains   = 'admgmt.ssncad.global'
            WalkTrust = $true
            OutCliXml = 'C:\temp\connectivity-results.xml'
        }
        Test-ADDomainConnectivity @params
        Exports results to CliXml file for firewall rule analysis

    .EXAMPLE
        $params = @{
            Domains   = 'admgmt.ssncad.global'
            WalkTrust = $true
            Port      = @(636, 389, 3268)
            OutCliXml = 'C:\temp\multi-port-results.xml'
        }
        Test-ADDomainConnectivity @params
        Tests connectivity on LDAPS (636), LDAP (389), and GC (3268) ports

    .NOTES
        Part of SSNC.ADInventory module
        Use this function to validate connectivity before running Start-ADInventoryCollection
    #>
    [CmdletBinding(DefaultParameterSetName = 'CurrentDomain')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ParameterSetName = 'CurrentDomain', Mandatory = $true)]
        [switch]$CurrentDomain,

        [Parameter(ParameterSetName = 'WalkTrust', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Domains')]
        [switch]$WalkTrust,

        [Parameter(ParameterSetName = 'Domains', Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domains,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
            foreach ($p in $_) {
                if ($p -lt 1 -or $p -gt 65535) {
                    throw "Port $p is not in valid TCP range (1-65535)"
                }
            }
            $true
        })]
        [int[]]$Port = @(636),

        [Parameter(Mandatory = $false)]
        [string]$LogFile,

        [Parameter(Mandatory = $false)]
        [string]$OutCliXml,

        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )

    begin {
        $startTime = Get-Date
        $results = [System.Collections.ArrayList]::new()
        $allDCResults = [System.Collections.ArrayList]::new()  # Detailed DC-level results
        $config = [ADQueryConfig]::new()

        # Helper function to get port description
        Function Get-PortDescription {
            Param ([int]$PortNumber)
            
            Switch ($PortNumber) {
                
                # 1-1023 - Well-known Ports
                53     { 'DNS (TCP/UDP)' } # DC locator, AD queries
                88     { 'Kerberos Authentication (TCP/UDP)' } # Auth and trust
                135    { 'RPC Endpoint Mapper' } # Required for many AD RPC calls
                139    { 'NetBIOS Session (Legacy)' } # Rarely needed today
                389    { 'LDAP (TCP/UDP)' } # Directory access
                445    { 'SMB (SYSVOL/NETLOGON, DFSR, GP)' } # Essential for logon + GPO
                464    { 'Kerberos Password Change/Set (TCP/UDP)' } # Password resets
                
                # 1024-49151 - Registered Ports
                5722   { 'FRS Replication (Legacy)' } # Pre-DFSR SYSVOL
                5985   { 'WinRM HTTP (PowerShell Remoting)' } # AD administration
                5986   { 'WinRM HTTPS (PowerShell Remoting)' }
                636    { 'LDAP over SSL (LDAPS)' } # Secure LDAP
                3260   { 'AD LDS Instance (LDAP)' } # AD LDS optional
                3261   { 'AD LDS Instance (LDAPS)' } # AD LDS SSL
                3268   { 'Global Catalog (GC)' } # Forest-wide search
                3269   { 'Global Catalog over SSL (GC-LDAPS)' } # Secure GC
                8530   { 'WSUS HTTP (Optional)' } # If DC runs WSUS
                8531   { 'WSUS HTTPS (Optional)' }
                
                # 49152-65535 - Dynamic / Ephemeral Ports
                9389   { 'Active Directory Web Services (ADWS)' } # AD PowerShell, LDS, etc.
                
                # Dynamic RPC range (Windows Server 2008+ default)
                { $_ -ge 49152 -and $_ -le 65535 } {
                    'Dynamic RPC Port' # Used for many AD RPC services
                }
                
                default { 'Custom or Unknown Port' }
            }
        }
        
        

        # Build port display string
        $portDisplayList = $Port | ForEach-Object { "$_ ($(Get-PortDescription $_))" }
        $portDisplayString = $portDisplayList -join ', '

        # Initialize log file if specified
        if ($LogFile) {
            $logHeader = @"
================================================================================
AD Domain Connectivity Test
================================================================================
Start Time:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Test Ports:     $portDisplayString
Parameter Set:  $($PSCmdlet.ParameterSetName)
================================================================================

"@
            Set-Content -Path $LogFile -Value $logHeader -Encoding UTF8
        }

        function Write-TestOutput {
            param([string]$Message, [string]$Color = 'White', [switch]$NoNewline)

            if (-not $Quiet) {
                $params = @{ Object = $Message; ForegroundColor = $Color; NoNewline = $NoNewline }
                Write-Host @params
            }
            if ($LogFile) {
                Add-Content -Path $LogFile -Value $Message -Encoding UTF8
            }
        }
    }

    process {
        try {
            # Resolve target domains using same logic as Start-ADInventoryCollection
            if (-not $Quiet) {
                Write-Host ""
                Write-Host "Resolving target domains..." -ForegroundColor Cyan
            }

            $domainList = switch ($PSCmdlet.ParameterSetName) {
                'CurrentDomain' {
                    Get-TargetDomainList -CurrentDomain
                }
                'WalkTrust' {
                    Get-TargetDomainList -WalkTrust
                }
                'Domains' {
                    if ($WalkTrust) {
                        Get-TargetDomainList -Domains $Domains -WalkTrust
                    }
                    else {
                        Get-TargetDomainList -Domains $Domains
                    }
                }
            }

            $totalDomains = $domainList.Count

            Write-TestOutput ""
            Write-TestOutput "=================================================================================="
            Write-TestOutput "  AD DOMAIN CONNECTIVITY TEST" -Color Cyan
            Write-TestOutput "=================================================================================="
            Write-TestOutput "  Domains to test: $totalDomains"
            Write-TestOutput "  Test ports:      $portDisplayString"
            Write-TestOutput "=================================================================================="
            Write-TestOutput ""

            if ($LogFile) {
                Add-Content -Path $LogFile -Value "Domains: $($domainList -join ', ')" -Encoding UTF8
                Add-Content -Path $LogFile -Value "" -Encoding UTF8
            }

            # Test each domain on each port
            $successCount = 0
            $failCount = 0
            $domainIndex = 0
            $totalTests = $domainList.Count * $Port.Count

            foreach ($domain in $domainList) {
                $domainIndex++

                Write-TestOutput "[$domainIndex/$totalDomains] " -Color Gray -NoNewline
                Write-TestOutput "$domain" -Color White

                # Resolve DCs via DNS first (same for all ports)
                $dnsRecords = $null
                $dnsFailed = $false
                $dnsError = $null

                try {
                    $dnsRecords = & {
                        Resolve-DnsName -Name $domain -ErrorAction Stop |
                            Where-Object {
                                $_.QueryType -ne "NS" -and
                                $_.Type -eq "A" -and
                                $_.Name -eq $domain
                            }
                    } 2>$null 3>$null 6>$null

                    if ($null -eq $dnsRecords -or @($dnsRecords).Count -eq 0) {
                        throw "No domain controllers found for $domain"
                    }
                }
                catch {
                    $dnsFailed = $true
                    $dnsError = $_.Exception.Message -replace "`r`n", " " -replace "`n", " "
                }

                $dcList = if ($dnsRecords) { @($dnsRecords) } else { @() }

                # Test each port for this domain
                foreach ($testPort in $Port) {
                    $portDesc = Get-PortDescription $testPort

                    $testResult = [PSCustomObject]@{
                        Domain        = $domain
                        Status        = 'Unknown'
                        DCsDiscovered = $dcList.Count
                        DCsAccessible = 0
                        BestDC        = $null
                        Latency       = $null
                        Port          = $testPort
                        PortDesc      = $portDesc
                        Error         = $null
                        TestedAt      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    }

                    Write-TestOutput "    Port $testPort ($portDesc) ... " -Color Gray -NoNewline

                    if ($dnsFailed) {
                        $testResult.Status = 'DNS Failed'
                        $testResult.Error = $dnsError
                        $failCount++
                        Write-TestOutput "FAILED" -Color Red -NoNewline
                        Write-TestOutput " | DNS Failed: $dnsError" -Color DarkYellow
                        [void]$results.Add($testResult)
                        continue
                    }

                    try {
                        $domainDCResults = [System.Collections.ArrayList]::new()

                        # Test each DC on this port
                        foreach ($dc in $dcList) {
                            $dcTestResult = & {
                                Test-ADConnectivity -ComputerName $dc.IPAddress `
                                    -Port $testPort `
                                    -TimeoutMilliseconds $config.DCTestTimeout `
                                    -MeasureLatency
                            } 2>$null 3>$null 6>$null

                            # Create detailed DC result object
                            $dcDetailResult = [PSCustomObject]@{
                                Domain      = $domain
                                DCIpAddress = $dc.IPAddress
                                Port        = $testPort
                                PortDesc    = $portDesc
                                Status      = if ($dcTestResult.PortOpen) { 'Pass' } else { 'Fail' }
                                Latency     = $dcTestResult.Latency
                                TestedAt    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            }

                            [void]$domainDCResults.Add($dcDetailResult)
                            [void]$allDCResults.Add($dcDetailResult)
                        }

                        # Calculate accessible DCs for this port
                        $accessibleDCs = $domainDCResults | Where-Object { $_.Status -eq 'Pass' }
                        $testResult.DCsAccessible = @($accessibleDCs).Count

                        if ($testResult.DCsAccessible -eq 0) {
                            throw "No accessible domain controllers found for $domain on port $testPort"
                        }

                        # Select best DC (lowest latency) for this port
                        $bestDC = $accessibleDCs | Sort-Object Latency | Select-Object -First 1
                        $testResult.Status = 'Success'
                        $testResult.BestDC = $bestDC.DCIpAddress
                        $testResult.Latency = $bestDC.Latency

                        $successCount++

                        # Console output
                        Write-TestOutput "OK" -Color Green -NoNewline
                        Write-TestOutput " | DC: $($testResult.BestDC) | Latency: $($testResult.Latency)ms | DCs: $($testResult.DCsAccessible)/$($testResult.DCsDiscovered)" -Color Gray
                    }
                    catch {
                        $errorMsg = $_.Exception.Message -replace "`r`n", " " -replace "`n", " "

                        # Determine failure type
                        if ($errorMsg -match 'No accessible') {
                            $testResult.Status = 'No DCs Accessible'
                        }
                        else {
                            $testResult.Status = 'Failed'
                        }

                        $testResult.Error = $errorMsg
                        $failCount++

                        # Console output
                        Write-TestOutput "FAILED" -Color Red -NoNewline
                        Write-TestOutput " | $($testResult.Status): $errorMsg" -Color DarkYellow
                    }

                    [void]$results.Add($testResult)
                }
            }

            # Summary
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds

            Write-TestOutput ""
            Write-TestOutput "=================================================================================="
            Write-TestOutput "  SUMMARY" -Color Cyan
            Write-TestOutput "=================================================================================="

            if ($successCount -eq $totalTests) {
                Write-TestOutput "  Status:     " -NoNewline
                Write-TestOutput "ALL TESTS PASSED" -Color Green
            }
            elseif ($successCount -gt 0) {
                Write-TestOutput "  Status:     " -NoNewline
                Write-TestOutput "PARTIAL SUCCESS" -Color Yellow
            }
            else {
                Write-TestOutput "  Status:     " -NoNewline
                Write-TestOutput "ALL TESTS FAILED" -Color Red
            }

            Write-TestOutput "  Domains:    $totalDomains"
            Write-TestOutput "  Ports:      $($Port.Count) ($($Port -join ', '))"
            Write-TestOutput "  Tests:      $totalTests (domains x ports)"
            Write-TestOutput "  Succeeded:  $successCount / $totalTests" -Color $(if ($successCount -eq $totalTests) { 'Green' } elseif ($successCount -gt 0) { 'Yellow' } else { 'Red' })
            Write-TestOutput "  Failed:     $failCount / $totalTests" -Color $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
            Write-TestOutput "  Duration:   $([math]::Round($duration, 2)) seconds"
            Write-TestOutput "=================================================================================="
            Write-TestOutput ""

            # List failed tests if any
            $failedTests = $results | Where-Object { $_.Status -ne 'Success' }
            if ($failedTests.Count -gt 0) {
                Write-TestOutput "  FAILED TESTS:" -Color Red
                Write-TestOutput "  --------------"
                foreach ($failed in $failedTests) {
                    Write-TestOutput "  - $($failed.Domain) : Port $($failed.Port) ($($failed.PortDesc))" -Color Yellow
                    Write-TestOutput "    Status: $($failed.Status)" -Color Gray
                    Write-TestOutput "    Error:  $($failed.Error)" -Color DarkGray
                }
                Write-TestOutput ""
            }

            # Log file summary
            if ($LogFile) {
                Add-Content -Path $LogFile -Value @"

================================================================================
SUMMARY
================================================================================
End Time:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Duration:       $([math]::Round($duration, 2)) seconds
Total Domains:  $totalDomains
Total Ports:    $($Port.Count) ($($Port -join ', '))
Total Tests:    $totalTests
Succeeded:      $successCount
Failed:         $failCount
================================================================================
"@ -Encoding UTF8

                Write-TestOutput "  Log file: $LogFile" -Color Gray
                Write-TestOutput ""
            }

            # Export to CliXml if requested
            if ($OutCliXml) {
                # Get source machine information
                $sourceIPs = @()
                try {
                    $sourceIPs = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                        Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                        ForEach-Object { $_.IPAddressToString }
                }
                catch {
                    $sourceIPs = @('Unable to resolve')
                }

                # Build port info array
                $portInfo = $Port | ForEach-Object {
                    [PSCustomObject]@{
                        Port        = $_
                        Description = Get-PortDescription $_
                    }
                }

                # Build DomainSummary array with per-domain/port statistics
                $domainSummary = $results | ForEach-Object {
                    [PSCustomObject]@{
                        Domain   = $_.Domain
                        Status   = $_.Status
                        BestDC   = $_.BestDC
                        Port     = $_.Port
                        PortDesc = $_.PortDesc
                        Total    = $_.DCsDiscovered
                        Pass     = $_.DCsAccessible
                        Fail     = $_.DCsDiscovered - $_.DCsAccessible
                    }
                }

                # Build export object with enhanced structure
                $exportObject = [PSCustomObject]@{
                    Summary = [PSCustomObject]@{
                        TestDate        = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
                        EndDate         = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
                        DurationSeconds = [math]::Round($duration, 2)
                        Ports           = @($portInfo)
                        TotalDomains    = $totalDomains
                        TotalPorts      = $Port.Count
                        TotalTests      = $totalTests
                        Succeeded       = $successCount
                        Failed          = $failCount
                        TotalDCsTested  = $allDCResults.Count
                        TotalDCsPassed  = @($allDCResults | Where-Object { $_.Status -eq 'Pass' }).Count
                        TotalDCsFailed  = @($allDCResults | Where-Object { $_.Status -eq 'Fail' }).Count
                        OverallStatus   = if ($successCount -eq $totalTests) { 'AllPassed' }
                                          elseif ($successCount -gt 0) { 'PartialSuccess' }
                                          else { 'AllFailed' }
                    }
                    SourceInfo = [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        IPAddresses  = $sourceIPs
                        UserName     = "$env:USERDOMAIN\$env:USERNAME"
                        Domain       = $env:USERDNSDOMAIN
                    }
                    DomainSummary = @($domainSummary)
                    DCInfo = $allDCResults.ToArray()
                }

                # Export to CliXml
                $exportObject | Export-Clixml -Path $OutCliXml -Depth 10

                Write-TestOutput "  CliXml export: $OutCliXml" -Color Gray
                Write-TestOutput ""
            }

            return $results.ToArray()
        }
        catch {
            Write-TestOutput ""
            Write-TestOutput "ERROR: $_" -Color Red

            if ($LogFile) {
                Add-Content -Path $LogFile -Value "ERROR: $_" -Encoding UTF8
            }

            throw
        }
    }
}
