<#
    .SYNOPSIS
        Retrieves computer objects from ActiveDirectory using an LDAP query
    
    .DESCRIPTION
        Powershell script to retrieve all computer objects from AD for import to validation database
    
    .PARAMETER WalkTrust
        A description of the WalkTrust parameter.
    
    .PARAMETER Domains
        A description of the Domains parameter.
    
    .NOTES
        ===========================================================================
        Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
        Created on:   	10/30/2024 3:33 PM
        Created by:   	DT234083
        Organization: 	SS&C
        Filename:     	Get-SSNCADInventory.ps1
        ===========================================================================
#>
[CmdletBinding(DefaultParameterSetName = 'CurrentDomain')]
Param
(
    [Parameter(ParameterSetName = 'WalkTrust', Mandatory = $true, Position = 0)]
    [switch]$WalkTrust,
    [Parameter(ParameterSetName = 'CurrentDomain', Mandatory = $true, Position = 0)]
    [switch]$CurrentDoamin,
    [Parameter(ParameterSetName = 'Domains', Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Domains
)


###########################################
##              FUNCTIONS                ##
###########################################

Function Convert-ByteToGuidString {
    Param ($v)
    Try {
        If ($v -is [byte[]]) {
            ([Guid]$v).ToString()
        } ElseIf ($v -is [Guid]) {
            $v.ToString()
        } Else {
            [Guid]::Parse($v.ToString()).ToString()
        }
    } Catch {
        $null
    }
}

Function Convert-ByteToSidString {
    Param ($v)
    Try {
        If ($v -is [byte[]]) {
            (New-Object System.Security.Principal.SecurityIdentifier($v, 0)).Value
        } ElseIf ($v -is [string]) { $v }
        Else { $null }
    } Catch { $null }
}

Function _GP {
    Param
    (
        [string]$n
    )
    
    If ($props.Contains($n) -and $props[$n].Count) {
        $props[$n][0]
    } Else { $null }
}

Function Convert-LargeIntToDate {
    Param ([object]$Value)
    If (-not $Value) { Return $null }
    Try {
        If ($Value -is [int64] -or $Value -is [string]) {
            $i64 = [int64]$Value
        } Else {
            # IADsLargeInteger (COM) -> Int64
            $high = [int64]$Value.HighPart
            $low  = [uint32]$Value.LowPart
            $i64  = ($high -shl 32) -bor $low
        }
        If ($i64 -le 0) { Return $null }
        [DateTime]::FromFileTimeUtc($i64)
    } Catch { $null }
}

Function Get-IPv4 {
    Param ([string]$DnsName)
    If ([string]::IsNullOrWhiteSpace($DnsName)) { Return $null }
    Try {
        [System.Net.Dns]::GetHostAddresses($DnsName) |
        Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
        Select-Object -First 1 -ExpandProperty IPAddressToString
    } Catch { $null }
}

Function Test-Port {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline = $true, HelpMessage = 'Could be suffixed by :Port')]
		[String[]]$ComputerName,
		[Parameter(HelpMessage = 'Will be ignored if the port is given in the param ComputerName')]
		[Int]$Port = 5985,
		[Parameter(HelpMessage = 'Timeout in millisecond. Increase the value if you want to test Internet resources.')]
		[Int]$Timeout = 1000
	)
	
	Begin {
		$result = [System.Collections.ArrayList]::new()
	}
	
	Process {
		ForEach ($originalComputerName In $ComputerName) {
			$remoteInfo = $originalComputerName.Split(":")
			If ($remoteInfo.count -eq 1) {
				# In case $ComputerName in the form of 'host'
				$remoteHostname = $originalComputerName
				$remotePort = $Port
			} ElseIf ($remoteInfo.count -eq 2) {
				# In case $ComputerName in the form of 'host:port',
				# we often get host and port to check in this form.
				$remoteHostname = $remoteInfo[0]
				$remotePort = $remoteInfo[1]
			} Else {
				$msg = "Got unknown format for the parameter ComputerName: " `
				+ "[$originalComputerName]. " `
				+ "The allowed formats is [hostname] or [hostname:port]."
				Write-Error $msg
				Return
			}
			
			$tcpClient = New-Object System.Net.Sockets.TcpClient
			$portOpened = $tcpClient.ConnectAsync($remoteHostname, $remotePort).Wait($Timeout)
			
			$null = $result.Add([PSCustomObject]@{
					RemoteHostname	     = $remoteHostname
					RemotePort		     = $remotePort
					PortOpened		     = $portOpened
					TimeoutInMillisecond = $Timeout
					SourceHostname	     = $env:COMPUTERNAME
					OriginalComputerName = $originalComputerName
				})
		}
	}
	
	End {
		Return $result
	}
}

Function Test-DomainADWS {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $false,
                   ValueFromPipeline = $true,
                   HelpMessage = 'Enter Domain Name')]
        [string]$DomainName,
        [ValidateRange(0, 65535)]
        [int]$Port = 9389
    )
    
    Begin {
        $result = [System.Collections.ArrayList]::new()
        $id = Get-Random
    }
    Process {
        $DCs = Resolve-DnsName -Name $DomainName -ErrorAction SilentlyContinue | Where-Object { $_.querytype -ne "NS" -and $_.type -eq "A" -and $_.name -eq $DomainName }
        
        If ($null -eq $DCs) { Throw "No DCs found" }
        
        $i = 0
        $TotalItems = $DCs.Count
        
        ForEach ($DC In $DCs) {
            $i++
            Write-Progress -Activity $DC.Name -PercentComplete ($i / $TotalItems * 100) -Status "DC $i of $TotalItems -- $($DC.IPAddress)" -Id $id
            $PortTest = Test-Port -ComputerName $DC.IPAddress -Port $Port
            
            $Latency = $null
            Try {
                $reply = Test-Connection -ComputerName $DC.IPAddress -Count 1 -ErrorAction Stop | Select-Object -First 1
                
                # Handle different property names across versions
                ForEach ($p In 'ResponseTime', 'Latency', 'RoundtripTime') {
                    If ($reply.PSObject.Properties.Match($p).Count) {
                        $Latency = [double]$reply.$p
                        Break
                    }
                }
            } Catch {
                $Latency = 99999
            }
            
            $null = $result.Add([PSCustomObject]@{
                    RemoteHostIP = $DC.IPAddress
                    PortOpened   = $PortTest.PortOpened
                    Latency      = $Latency
                    Doamin       = $DomainName
                })
        }
    }
    End {
        Write-Progress -Activity $DC.Name -Id $id -Completed
        Return $result
    }
}

Function Get-ADInventory {
    [CmdletBinding()]
    Param (
        [Parameter()]
        [string]$OutputPath = ".\",
        [Parameter()]
        [string]$Server,
        [Parameter()]
        [string]$DomainName,
        [ValidateSet('Csv', 'Ndjson', 'Clixml')]
        [string]$OutputType = 'Csv',
        [int]$PageSize = 1000,
        [int]$FlushEvery = 5000,
        # how many rows to buffer before flushing (CSV/CLIXML)
        [int]$MaxObjectsPerFile = 50000,
        # CLIXML only: split files this big
        [switch]$ResolveIP,
        # resolve IPv4 via DNS (slows down large runs)
        [System.Management.Automation.PSCredential]$Credential,
        [string]$LdapFilter = '(&(objectCategory=computer)(objectClass=computer))',
        [string[]]$Properties = @(
            'name', 'description', 'operatingsystem', 'operatingsystemversion', 'operatingsystemservicepack', 'IPv4Address'
            'pwdlastset', 'lastlogon', 'lastlogontimestamp', 'canonicalname', 'dnshostname', 'distinguishedname',
            'objectguid', 'objectsid', 'useraccountcontrol', 'objectGUID', 'objectSID', 'displayname', 'adminDescription', 'adminDisplayName'
        )
    )
    
    Begin {
        
        $InventoryID = [guid]::NewGuid().ToString()
        
        Write-Verbose "New Inventory ID Created = $InventoryID"

        # Resolve base DN ########################################################################
        $baseDN = $null
        If ($DomainName) {
            $baseDN = 'DC=' + (($DomainName -split '\.') -join ',DC=')
        } Else {
            Try {
                $rootPath = If ($Server) { "LDAP://$Server/RootDSE" } Else { "LDAP://RootDSE" }
                $root = [ADSI]$rootPath
                $baseDN = $root.defaultNamingContext
            } Catch {
                Throw "Could not determine defaultNamingContext. Specify -DomainName."
            }
        }
        
        $ts = Get-Date
        $tsStamp = $ts.ToString('yyyyMMdd-HHmmss')
        $outBase = If ($DomainName) { $DomainName } Else { ($baseDN -replace 'DC=', '' -replace ',', '.') }
        $ext = Switch ($OutputType) { 'Csv'{ 'csv' } 'Ndjson'{ 'json' } default{ 'xml' } }
        $outPath = Join-Path -Path $OutputPath -ChildPath "$tsStamp`_$outBase.$ext"
        
        Write-Verbose "Output File name = $outPath"
        
        # Prepare output sinks ###################################################################
        $csvHeaderWritten = $false
        $buffer = New-Object System.Collections.Generic.List[object]
        $fileIndex = 1
        $ndjsonWriter = $null
        
        If ($OutputType -eq 'Csv') {
            If (Test-Path $outPath) { Remove-Item $outPath -Force }
        } ElseIf ($OutputType -eq 'Ndjson') {
            $ndjsonWriter = New-Object System.IO.StreamWriter($outPath, $false, [Text.Encoding]::UTF8)
        } ElseIf ($OutputType -eq 'Clixml') {
            # we will split into numbered files to avoid memory spikes
            If (Test-Path $outPath) { Remove-Item $outPath -Force }
        }
        
        # Bind DirectoryEntry / DirectorySearcher ################################################
        $ldapPath = If ($Server) { "LDAP://$Server/$baseDN" } Else { "LDAP://$baseDN" }
        If ($Credential) {
            $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $Credential.UserName, $Credential.GetNetworkCredential().Password)
        } Else {
            $de = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
        }
        
        $ds = New-Object System.DirectoryServices.DirectorySearcher($de)
        $ds.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $ds.PageSize = $PageSize
        #$ds.CacheResults = $false
        $ds.Asynchronous = $true
        $ds.ReferralChasing = [System.DirectoryServices.ReferralChasingOption]::None
        $ds.Filter = $LdapFilter
        $ds.PropertiesToLoad.Clear() | Out-Null
        ForEach ($p In $Properties) { [void]$ds.PropertiesToLoad.Add($p) }
        
        $total = 0
        $srctotal = 0
        Write-Verbose "Searching baseDN: $baseDN  (Server: $Server)  PageSize: $PageSize"
    }
    Process {
        $src = $null
        Try {
            $src = $ds.FindAll() # SearchResultCollection (paged)
            
            $activity = "Processing results"
            $srctotal = $src.Count
            $ii = 0
            $ID2 = Get-Random
            $updateFrequency = 100
            
            Write-Verbose ("Starting to process results: {0:n0}" -f $srctotal)
            
            ForEach ($res In $src) {
                $ii++
                
                If (($ii % $updateFrequency) -eq 0 -or $ii -eq $srctotal) {
                    $pct = If ($srctotal -gt 0) {
                        [int](($ii / $srctotal) * 100)
                    } Else {
                        0
                    }
                    
                    Write-Progress -Id $ID2 -Activity $activity -Status ("Processed $ii of $srctotal $pct%") -PercentComplete $pct
                }
                
                $props = $res.Properties
                
                $pwdLastSetDate = Convert-LargeIntToDate (_GP 'pwdLastSet')
                $lastLogonDate_raw = Convert-LargeIntToDate (_GP 'lastLogon')
                $lastLogonTimestamp_dt = Convert-LargeIntToDate (_GP 'lastLogonTimestamp')
                $effectiveLastLogon = $lastLogonTimestamp_dt # match AD module's LastLogonDate behavior
                
                $dns = _GP 'dNSHostName'
                $ipv4 = If ($ResolveIP) { Get-IPv4 -DnsName $dns } Else { $null }
                
                $uac = 0
                $uacRaw = _GP 'useraccountcontrol'
                If ($uacRaw) { [void][int]::TryParse($uacRaw.ToString(), [ref]$uac) }
                $enabled = -not ([bool]($uac -band 0x0002)) # ACCOUNTDISABLE bit
                
                $guidStr = Convert-ByteToGuidString $res.Properties.objectguid[0]
                $sidStr = Convert-ByteToSidString $res.Properties.objectsid[0]
                
                $row = [pscustomobject]@{
                    InventoryID = $InventoryID
                    Name = _GP 'name'
                    Description = _GP 'description'
                    OperatingSystem = _GP 'operatingsystem'
                    OperatingSystemVersion = _GP 'operatingsystemversion'
                    OperatingSystemServicePack = _GP 'operatingsystemservicepack'
                    IPv4Address = $ipv4
                    LastLogonDate = $effectiveLastLogon
                    pwdLastSet = $pwdLastSetDate
                    lastLogon = $lastLogonDate_raw
                    lastLogonTimestamp = $lastLogonTimestamp_dt
                    CanonicalName = _GP 'canonicalname'
                    DNSHostName = $dns
                    DistinguishedName = _GP 'distinguishedname'
                    ObjectGUID = $guidStr
                    SID  = $sidStr
                    Enabled = $enabled
                    adminDisplayName = _GP 'adminDisplayName'
                    adminDescription = _GP 'adminDescription'
                    displayName = _GP 'displayName'
                }
                
                
                Switch ($OutputType) {
                    'Csv' {
                        $buffer.Add($row) | Out-Null
                        If ($buffer.Count -ge $FlushEvery) {
                            If (-not $csvHeaderWritten) {
                                $buffer | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
                                $csvHeaderWritten = $true
                            } Else {
                                $buffer | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Append
                            }
                            $buffer.Clear()
                        }
                    }
                    'Ndjson' {
                        $ndjsonWriter.WriteLine(($row | ConvertTo-Json -Depth 6 -Compress))
                    }
                    'Clixml' {
                        $buffer.Add($row) | Out-Null
                        If ($buffer.Count -ge $MaxObjectsPerFile) {
                            $chunkPath = Join-Path $OutputPath "$outBase.$('{0:d4}' -f $fileIndex).xml"
                            $buffer | Export-Clixml -Path $chunkPath
                            $buffer.Clear()
                            $fileIndex++
                        }
                    }
                }
                
                $total++
                If ($total % 5000 -eq 0) { Write-Verbose ("Processed {0:n0} objects..." -f $total) }
            }
        } Finally {
            If ($src -is [System.IDisposable]) { $src.Dispose() }
            Write-Progress -Id $ID2 -Activity $activity -Completed
        }
    }
    End {
        Try {
            Switch ($OutputType) {
                'Csv' {
                    If ($buffer.Count) {
                        If (-not $csvHeaderWritten) {
                            $buffer | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
                        } Else {
                            $buffer | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Append
                        }
                        $buffer.Clear()
                    }
                    Write-Verbose "CSV written to: $outPath"
                    $outPath
                }
                'Ndjson' {
                    If ($ndjsonWriter) { $ndjsonWriter.Flush(); $ndjsonWriter.Dispose() }
                    Write-Verbose "NDJSON written to: $outPath"
                    $outPath
                }
                'Clixml' {
                    If ($buffer.Count) {
                        $chunkPath = If ($fileIndex -eq 1) {
                            # if we never overflowed, use the main name
                            Join-Path $OutputPath "$outBase.xml"
                        } Else {
                            Join-Path $OutputPath "$outBase.$('{0:d4}' -f $fileIndex).xml"
                        }
                        $buffer | Export-Clixml -Path $chunkPath
                        $buffer.Clear()
                    }
                    If ($fileIndex -eq 1) {
                        Write-Verbose "CLIXML written to: $(Join-Path $OutputPath "$outBase.xml")"
                    } Else {
                        Write-Verbose "CLIXML chunks written with base: $outBase.0001.xml ..."
                    }
                }
            }
        } Finally {
            If ($ds) { $ds.Dispose() }
            If ($de) { $de.Dispose() }
        }
        Write-Verbose ("Total objects processed: {0:n0}" -f $total)
    }
}

###########################################
##               SCRIPT                  ##
###########################################

$CurrentDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
$DomainList = [System.Collections.ArrayList]::new()

Switch ($PSCmdlet.ParameterSetName) {
    'CurrentDomain' {
        #add only the current domain to the list
        [void]$DomainList.Add($CurrentDomain.Name)
    }
    'WalkTrust'{
        #add the current domain and then add the trusted domains
        [void]$DomainList.Add($CurrentDomain.Name)
        
        # Collecting trusted domains
        #(Get-ADTrust -Filter 'Direction -eq "Inbound"').Target | ForEach-Object { [void]$DomainList.Add($_) }
        
        #use .net calls in place of AD cmdlets 
        Try {
            $trusts = $CurrentDomain.GetAllTrustRelationships() # TrustRelationshipInformation[]
            $inbound = $trusts | Where-Object {
                $_.TrustDirection -in @(
                    [System.DirectoryServices.ActiveDirectory.TrustDirection]::Inbound,
                    [System.DirectoryServices.ActiveDirectory.TrustDirection]::Bidirectional
                )
            }
            
            $inbound.TargetName | ForEach-Object { [void]$DomainList.Add($_) }
        } Catch {
            Throw "Not domain-joined or cannot contact a DC"
            Exit 101
        }
        
    }
    'Domains' {
        # Only add the domains specified
        $Domains | ForEach-Object { [void]$DomainList.Add($_) }
    }
}

# Initialize progress bar variables
$TotalDomains = $DomainList.Count
$ProcessedDomains = 0

If ($TotalDomains -eq 0) {
    Throw "No domains to be processed, exiting"
    exit 102
}

ForEach ($Domain In $DomainList) {
	# Update progress bar
	$ProcessedDomains++
    Write-Progress -Activity "Processing Domains - ($ProcessedDomains of $TotalDomains)" -Status "Starting $Domain" -PercentComplete ([math]::Round(($ProcessedDomains / $TotalDomains) * 100, 2))
    
    Write-Host "Starting $Domain"
    Try {
        $ADWSDCs = Test-DomainADWS -DomainName $Domain -Port 636
    } Catch {
        Write-Host "No DCs found or domain can not be resolved." -ForegroundColor Red
        continue
    }
    $DCToQuery = $ADWSDCs | Where-Object { $_.PortOpened -eq $true } | Sort-Object Latency | Select-Object -First 1 -ExpandProperty RemoteHostIP
	
	If ($DCToQuery) {
		Write-Output "Connecting to $DCToQuery to collect Active Directory data for $Domain"
        Get-ADInventory -Server $DCToQuery -DomainName $Domain -ResolveIP -Verbose
 	} Else {
		Write-Output "Could not connect to Active Directory Web Services on $Domain"
	}
}

# Complete the progress bar
Write-Progress -Activity "Processing Domains" -Completed



<#
# DNS domain by name (no AD cmdlets)
$DomainContext = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new('Domain', 'ad.dstsystems.com')
$domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContext)

# get the pdc
$pdc = $domain.PdcRoleOwner

# trusts (typed objects)
$trusts = $domain.GetAllTrustRelationships()
$trusts | Select-Object SourceName, TargetName, TrustType, TrustDirection



# SCP Stuff
https://chadbaldwin.net/2021/11/01/sftp-in-powershell.html

# install module
Install-Module winscp

# import module into current session
Import-Module winscp

# Execute stored procedure usp_ExportData
# Export data as tab delimited, with double quote qualifiers to 'export.csv'
Invoke-DbaQuery -SqlInstance ServerA -Database DBFoo `
                -CommandType StoredProcedure -Query 'usp_ExportData' |
    Export-Csv -Path .\export.csv -Delimiter '|'

# Manually get credentials
# Could also use database, Amazon Secrets, Vault, SecretStore, config file, etc
$credential = Get-Credential

$options = @{
  Credential = $credential # This will provide the Username and Password
  Protocol = 'Sftp'
  HostName = 'sftp.someclient.com'
  GiveUpSecurityAndAcceptAnySshHostKey = $true
}

# Configure options for the session
$sessionOption = New-WinSCPSessionOption @options

# Open connection to server
$session = New-WinSCPSession -SessionOption $sessionOption

# Send export file to server via SFTP connection
Send-WinSCPItem -WinSCPSession $session -LocalPath .\export.csv

# Disconnect and dispose of connection
Remove-WinSCPSession -WinSCPSession $session







#>


