<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	10/31/2025 2:04 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



Function Get-RemoteDNSConfig {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]$ComputerListPath,
        [int]$ThrottleLimit = 30,
        [int]$TimeoutSec = 15
    )
    
    # Load list of computers
    $computers = Get-Content -Path $ComputerListPath | Where-Object { $_.Trim() -ne '' }
    
    Write-Host "Starting DNS configuration collection for $($computers.Count) computers..." -ForegroundColor Cyan
    
    $results = $computers | ForEach-Object -Parallel {
        $computer = $_
        Try {
            # Test if reachable before session creation
            If (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                Throw "Host unreachable"
            }
            
            # Query DNS configuration remotely
            $r = Invoke-Command -ComputerName $computer -ScriptBlock {
                Get-DnsClientServerAddress -AddressFamily ipv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|isatap|Teredo' } |
                Select-Object -Property `
                              @{ n = 'ComputerName'; e = { $env:COMPUTERNAME } },
                              InterfaceAlias,
                              ConnectionSpecificSuffix,
                              @{ n = 'DNSServerAddresses'; e = { ($_.ServerAddresses -join ', ') } }
            } -ErrorAction Stop
            
            If (-not $r) {
                Throw "No DNS configuration returned"
            }
            
            $r
        } Catch {
            [PSCustomObject]@{
                ComputerName             = $computer
                InterfaceAlias           = $null
                ConnectionSpecificSuffix = $null
                DNSServerAddresses       = $null
                Error                    = $_.Exception.Message
            }
        }
    } -ThrottleLimit $ThrottleLimit
    
    Write-Host "Collection complete." -ForegroundColor Green
    Return $results
}



$Scriptblock = {
    Function Get-LocalComputerADSite {
        [CmdletBinding()]
        Param ()
        
        Try {
            Add-Type -AssemblyName System.DirectoryServices
            
            $site = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite()
            Return $site.Name
        } Catch {
            Write-Error "Unable to determine AD site: $_"
            Return $null
        }
    }
    
    Function Get-LocalComputerADSite {
        [CmdletBinding()]
        Param ()
        
        Try {
            $output = nltest /dsgetsite
            If ($LASTEXITCODE -eq 0) {
                Return $output[0].Trim()
            } Else {
                Write-Error "nltest failed or domain not joined."
                Return $null
            }
        } Catch {
            Write-Error "Unable to determine AD site: $_"
            Return $null
        }
    }
    
    Function Get-DNSValBySite {
        $ADSite = Get-LocalComputerADSite
        
        Switch ($ADSite) {
            'JA-TO-Core' {
                Return @('100.98.128.20', '100.98.128.26', '100.98.128.142')
            }
            'RS-Sing-Core' {
                Return @('100.98.128.142', '100.98.128.146', '100.98.128.20')
            }
            'UK-Marshfield-NG-Core' {
                Return @('100.98.24.8', '100.98.24.8', '100.98.16.9')
            }
            'UK-Harlow-KAO-Core' {
                Return @('100.98.16.9', '100.98.16.10', '100.98.24.8')
            }
            'US-MO-WDC-Core' {
                Return @('100.98.0.8', '100.98.0.9', '100.98.8.4')
            }
            'US-MO-STL-Core' {
                Return @('100.98.8.4', '100.98.8.5', '100.98.0.8')
            }
            default {
                Throw "Unrecognized AD Site: $ADSite"
            }
        }
    }
    
    Function Set-PrimaryNICDNS {
        [CmdletBinding(SupportsShouldProcess = $true)]
        Param (
            [switch]$Force
        )
        
        Try {
            # Get the AD site and corresponding DNS servers
            $ADSite = Get-LocalComputerADSite
            If (-not $ADSite) {
                Throw "Unable to determine AD site. Cannot proceed with DNS update."
            }
            
            Write-Host "Detected AD Site: $ADSite" -ForegroundColor Cyan
            
            # Get DNS servers for this site
            $DNSServers = Get-DNSValBySite
            Write-Host "DNS Servers for site: $($DNSServers -join ', ')" -ForegroundColor Cyan
            
            # Get the primary network adapter (the one with the default gateway)
            $PrimaryAdapter = Get-NetAdapter | Where-Object {
                $_.Status -eq 'Up' -and
                (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4DefaultGateway
            } | Select-Object -First 1
            
            If (-not $PrimaryAdapter) {
                Throw "Unable to identify primary network adapter."
            }
            
            Write-Host "`nPrimary Network Adapter:" -ForegroundColor Green
            Write-Host "  Name: $($PrimaryAdapter.Name)" -ForegroundColor White
            Write-Host "  Description: $($PrimaryAdapter.InterfaceDescription)" -ForegroundColor White
            Write-Host "  Status: $($PrimaryAdapter.Status)" -ForegroundColor White
            
            # Get current DNS settings
            $CurrentDNS = (Get-DnsClientServerAddress -InterfaceIndex $PrimaryAdapter.ifIndex -AddressFamily IPv4).ServerAddresses
            Write-Host "`nCurrent DNS Servers: $($CurrentDNS -join ', ')" -ForegroundColor Yellow
            
            # Compare current and new DNS settings
            $DNSMatch = $true
            If ($CurrentDNS.Count -ne $DNSServers.Count) {
                $DNSMatch = $false
            } Else {
                For ($i = 0; $i -lt $CurrentDNS.Count; $i++) {
                    If ($CurrentDNS[$i] -ne $DNSServers[$i]) {
                        $DNSMatch = $false
                        Break
                    }
                }
            }
            
            If ($DNSMatch) {
                Write-Host "`nDNS servers are already correctly configured. No changes needed." -ForegroundColor Green
                Return
            }
            
            # Prompt for confirmation unless -Force is used
            If (-not $Force -and -not $PSCmdlet.ShouldProcess($PrimaryAdapter.Name, "Update DNS servers to: $($DNSServers -join ', ')")) {
                $response = Read-Host "`nDo you want to update DNS servers? (Y/N)"
                If ($response -notmatch '^[Yy]') {
                    Write-Host "DNS update cancelled by user." -ForegroundColor Yellow
                    Return
                }
            }
            
            # Update DNS servers
            Write-Host "`nUpdating DNS servers..." -ForegroundColor Cyan
            Set-DnsClientServerAddress -InterfaceIndex $PrimaryAdapter.ifIndex -ServerAddresses $DNSServers
            
            # Verify the change
            Start-Sleep -Seconds 2
            $NewDNS = (Get-DnsClientServerAddress -InterfaceIndex $PrimaryAdapter.ifIndex -AddressFamily IPv4).ServerAddresses
            
            Write-Host "`nDNS Update Complete!" -ForegroundColor Green
            Write-Host "New DNS Servers: $($NewDNS -join ', ')" -ForegroundColor Green
            
            # Flush DNS cache
            Write-Host "`nFlushing DNS cache..." -ForegroundColor Cyan
            Clear-DnsClientCache
            Write-Host "DNS cache cleared successfully." -ForegroundColor Green
            
        } Catch {
            Write-Error "Failed to update DNS settings: $_"
            Return $false
        }
    }
    
    # Main execution
    Write-Host "=== Primary NIC DNS Configuration Update ===" -ForegroundColor Magenta
    Write-Host "=== $ENV:COMPUTERNAME ===" -ForegroundColor Magenta
    Write-Host ""
    
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    If (-not $isAdmin) {
        Write-Warning "This script requires administrator privileges to modify DNS settings."
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        Exit
    }
    
    # Execute the DNS update
    Set-PrimaryNICDNS
}
    