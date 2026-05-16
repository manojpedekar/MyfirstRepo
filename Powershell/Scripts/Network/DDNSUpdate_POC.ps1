Function Set-DnsDynamicRegistrationTTL {
    <#
    .SYNOPSIS
        Sets the DefaultRegistrationTTL registry value and (optionally) restarts the
        DNS Client (Dnscache) service so the new TTL is picked up.

    .PARAMETER Seconds
        TTL in seconds.  3600 = 1 hour, 86400 = 1 day, etc.

    .PARAMETER SkipServiceRestart
        Do not restart the DNS Client service after changing the registry.

    .PARAMETER PassThru
        Emit an object with the old TTL, new TTL, and whether the service was restarted.

    .EXAMPLE
        Set-DnsDynamicRegistrationTTL -Seconds 3600
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, 2592000)]
        [int]$Seconds = 1200,
        [switch]$SkipServiceRestart,
        [switch]$PassThru
    )
    
    # ---------- guard rails ----------
    If (-not ([bool](Get-Process -Id $PID -IncludeUserName).Path)) { } # warms up for Try/Catch
    If (-not (Test-Path -LiteralPath 'HKLM:\')) {
        Throw 'This function must run on Windows.'
    }
    If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        Throw 'Administrator privileges are required to modify HKLM and restart services.'
    }
    
    # ---------- constants ----------
    $KeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    $ValueName = 'DefaultRegistrationTTL'
    
    Try {
        $oldTtl = (Get-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    } Catch {
        $oldTtl = $null
    }
    
    If ($oldTtl -eq $Seconds) {
        Write-Verbose "Current TTL already $Seconds s - no change needed."
        $changed = $false
    } Else {
        If ($PSCmdlet.ShouldProcess("$KeyPath\$ValueName", "Set to $Seconds (was $oldTtl)")) {
            Try {
                New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType DWord `
                                 -Value $Seconds -Force -ErrorAction Stop | Out-Null
                $changed = $true
            } Catch {
                Throw "Failed to set registry key: $_"
            }
        }
    }
    
    $serviceRestarted = $false
    If ($changed -and -not $SkipServiceRestart) {
        If ($PSCmdlet.ShouldProcess('Dnscache', 'Restart service')) {
            Try {
                Restart-Service -Name 'Dnscache' -Force -ErrorAction Stop
                $serviceRestarted = $true
            } Catch {
                Throw "Registry updated, but restarting service failed: $_"
            }
        }
    }
    
    If ($PassThru) {
        [pscustomobject]@{
            OldTTL           = $oldTtl
            NewTTL           = $Seconds
            RegistryChanged  = $changed
            ServiceRestarted = $serviceRestarted
        }
    }
}

Function Get-SiteDomainControllers {
    
    <#
    .SYNOPSIS
        Enumerate the IP addresses of the domain controllers in the
        Active Directory site where the local computer is located.

    .NOTES
        • Requires only built-in .NET + DNS Client cmdlets
        • Works on Windows Server 2008 R2 + / Windows 10 + (fallbacks included)
    #>
    
    
    [CmdletBinding()]
    Param ()
    
    # ---------- 1. Determine the computer's AD site ----------
    Try {
        $siteName = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name
    } Catch {
        # Fallback: read the NetLogon registry key (works even on Core)
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
        $siteName = (Get-ItemProperty -Path $regPath -Name DynamicSiteName, SiteName -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DynamicSiteName) 
    }
    
    # ---------- 2. Build the SRV record name ----------
    $domainName = ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name
    # _ldap._tcp.<Site>._sites.dc._msdcs.<Forest root>
    $srvName = "_ldap._tcp.$siteName._sites.dc._msdcs.$domainName"
    
    # ---------- 3. Look up that SRV record ----------
    Try {
        $srvRecords = Resolve-DnsName -Name $srvName -Type SRV -ErrorAction Stop
    } Catch {
        # Older OS (no Resolve-DnsName) → fallback to nslookup
        $srvText = nslookup -type=srv $srvName 2>$null
        $srvRecords = ForEach ($line In $srvText) {
            If ($line -match 'service = (\S+)$') {
                [pscustomobject]@{ NameTarget = $Matches[1] }
            }
        }
    }
    
    If (-not $srvRecords) {
        Write-Warning "No SRV records found for $srvName"
        Return
    }
    
    # ---------- 4. Resolve host names to IP addresses ----------
    $results = ForEach ($record In $srvRecords |
        Sort-Object -Property @{ e = 'Priority' }, @{ e = 'Weight' }, @{ e = 'NameTarget' } |
        Select-Object -ExpandProperty NameTarget -Unique) {
        
        # Collect A records (IPv4 only)
        Try {
            $ips = Resolve-DnsName -Name $record -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            Select-Object -ExpandProperty IPAddress
        } Catch {
            # Fallback for older OS
            $ips = ([System.Net.Dns]::GetHostAddresses($record)).IPAddressToString
        }
        
        [pscustomobject]@{
            Site             = $siteName
            DomainController = $record.TrimEnd('.')
            IPAddress        = $ips
        }
    }
    
    Return $results
}

# Invoke the function
Get-SiteDomainControllers 


