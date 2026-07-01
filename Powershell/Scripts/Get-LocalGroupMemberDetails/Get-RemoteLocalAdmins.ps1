<#
	.SYNOPSIS
		Lists all members of the local Administrators group across multiple servers.

	.DESCRIPTION
		Connects to each server supplied via -ComputerName (or a file via -ComputerListPath)
		and enumerates the members of the local Administrators group. By default it uses
		PowerShell Remoting (WinRM), which runs the enumeration ON the remote host and avoids
		the SMB/RPC ("network path was not found") failures seen with the WinNT/ADSI provider on
		firewalled or segmented servers. If WinRM fails, it falls back to the ADSI (WinNT) method.
		Results are written to the pipeline and, unless -NoExport is specified, exported to a
		single consolidated timestamped CSV.

	.PARAMETER ComputerName
		One or more server names to query. Defaults to the local computer.

	.PARAMETER ComputerListPath
		Path to a text file containing one server name per line. Combined with -ComputerName if both are given.

	.PARAMETER GroupName
		The local group to enumerate. Defaults to "Administrators".

	.PARAMETER LogPath
		Directory where the CSV output is written. Defaults to C:\audit.

	.PARAMETER Credential
		Optional credential used for the WinRM connection. Prompt with (Get-Credential).

	.PARAMETER UseADSI
		Force the legacy ADSI (WinNT) method instead of WinRM.

	.PARAMETER NoExport
		Skip writing the CSV; results are only returned to the pipeline.

	.EXAMPLE
		PS C:\> .\Get-RemoteLocalAdmins.ps1 -ComputerListPath .\servers.txt -Verbose

	.EXAMPLE
		PS C:\> .\Get-RemoteLocalAdmins.ps1 -ComputerName SERVER01 -Credential (Get-Credential)
#>
[CmdletBinding()]
Param
(
	[Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
	[Alias('CN', 'Server', 'Computer')]
	[string[]]$ComputerName = $env:COMPUTERNAME,
	[ValidateScript({ Test-Path $_ })]
	[string]$ComputerListPath,
	[string]$GroupName = "Administrators",
	[string]$LogPath = "c:\audit",
	[System.Management.Automation.PSCredential]$Credential,
	[switch]$UseADSI,
	[switch]$NoExport
)

# Scriptblock that runs ON the remote host via WinRM. Uses ADSI locally (so no remote SMB hop),
# which keeps it compatible with older servers that lack the Get-LocalGroupMember cmdlet.
$RemoteScript = {
	Param ($Group)

	$GroupObj = [ADSI]"WinNT://./$Group,group"
	$Members = $GroupObj.psbase.Invoke("Members")

	ForEach ($Member In $Members) {
		$Name = $Member.GetType().InvokeMember("Name", 'GetProperty', $null, $Member, $null)
		$Class = $Member.GetType().InvokeMember("Class", 'GetProperty', $null, $Member, $null)
		$AdsPath = $Member.GetType().InvokeMember("ADsPath", 'GetProperty', $null, $Member, $null)
		$Domain = ($AdsPath -replace '^WinNT://', '' -split '/')[0]

		Try {
			$NTAccount = New-Object System.Security.Principal.NTAccount($Domain, $Name)
			$Sid = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
		} Catch {
			$Sid = ""
		}

		New-Object -TypeName PSObject -Property @{
			'LocalGroup' = $Group; 'Member' = $Name; 'Domain' = $Domain; 'Type' = $Class; 'SID' = $Sid; 'Path' = $AdsPath
		}
	}
}

Function ConvertTo-ResultRow {
	Param ($Computer, $Group, $Obj, $ErrorText)
	If ($ErrorText) {
		New-Object -TypeName PSObject -Property @{
			'ComputerName' = $Computer; 'LocalGroup' = $Group; 'Member' = ''; 'Domain' = '';
			'Type' = ''; 'SID' = ''; 'Path' = "ERROR: $ErrorText"
		} | Select-Object ComputerName, LocalGroup, Member, Domain, Type, SID, Path
	} Else {
		New-Object -TypeName PSObject -Property @{
			'ComputerName' = $Computer; 'LocalGroup' = $Obj.LocalGroup; 'Member' = $Obj.Member; 'Domain' = $Obj.Domain;
			'Type' = $Obj.Type; 'SID' = $Obj.SID; 'Path' = $Obj.Path
		} | Select-Object ComputerName, LocalGroup, Member, Domain, Type, SID, Path
	}
}

# Legacy ADSI (WinNT) path -- reaches the remote host over SMB/RPC. Kept as a fallback.
Function Get-LocalGroupMembersADSI {
	Param ($Computer, $Group)

	$GroupObj = [ADSI]"WinNT://$Computer/$Group,group"
	$Members = $GroupObj.psbase.Invoke("Members")

	ForEach ($Member In $Members) {
		$Name = $Member.GetType().InvokeMember("Name", 'GetProperty', $null, $Member, $null)
		$Class = $Member.GetType().InvokeMember("Class", 'GetProperty', $null, $Member, $null)
		$AdsPath = $Member.GetType().InvokeMember("ADsPath", 'GetProperty', $null, $Member, $null)
		$Domain = ($AdsPath -replace '^WinNT://', '' -split '/')[0]

		Try {
			$NTAccount = New-Object System.Security.Principal.NTAccount($Domain, $Name)
			$Sid = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
		} Catch {
			$Sid = ""
		}

		ConvertTo-ResultRow -Computer $Computer -Group $Group -Obj (New-Object -TypeName PSObject -Property @{
			'LocalGroup' = $Group; 'Member' = $Name; 'Domain' = $Domain; 'Type' = $Class; 'SID' = $Sid; 'Path' = $AdsPath
		})
	}
}

##############################################################
# Begin Main Script
##############################################################

# Build the full list of computers to query
$Computers = @()
$Computers += $ComputerName
If ($ComputerListPath) {
	$Computers += Get-Content -Path $ComputerListPath | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
}
$Computers = $Computers | Select-Object -Unique

# Common args for Invoke-Command
$ICArgs = @{ ScriptBlock = $RemoteScript; ArgumentList = $GroupName; ErrorAction = 'Stop' }
If ($Credential) { $ICArgs['Credential'] = $Credential }

$Results = @()

ForEach ($Computer In $Computers) {
	Write-Verbose "Querying '$Computer' for members of '$GroupName'..."

	If ($UseADSI) {
		# Explicit legacy path
		Try {
			$Results += Get-LocalGroupMembersADSI -Computer $Computer -Group $GroupName
		} Catch {
			Write-Warning "ADSI query failed for '$Computer': $($_.Exception.Message)"
			$Results += ConvertTo-ResultRow -Computer $Computer -Group $GroupName -ErrorText $_.Exception.Message
		}
		Continue
	}

	# Primary path: WinRM (runs on the remote host, avoids SMB/RPC firewall issues)
	Try {
		$Remote = Invoke-Command @ICArgs -ComputerName $Computer
		ForEach ($r In $Remote) {
			$Results += ConvertTo-ResultRow -Computer $Computer -Group $GroupName -Obj $r
		}
	} Catch {
		$WinRMError = $_.Exception.Message
		Write-Warning "WinRM failed for '$Computer' ($WinRMError). Falling back to ADSI..."

		# Fallback path: ADSI over SMB/RPC
		Try {
			$Results += Get-LocalGroupMembersADSI -Computer $Computer -Group $GroupName
		} Catch {
			Write-Warning "ADSI fallback also failed for '$Computer': $($_.Exception.Message)"
			$Results += ConvertTo-ResultRow -Computer $Computer -Group $GroupName -ErrorText "WinRM: $WinRMError | ADSI: $($_.Exception.Message)"
		}
	}
}

If (-not $NoExport) {
	If (!(Test-Path $LogPath)) { New-Item $LogPath -ItemType Directory | Out-Null }
	$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
	$OutFile = Join-Path $LogPath "RemoteLocalAdmins-$Stamp.csv"
	$Results | Export-Csv -Path $OutFile -NoTypeInformation
	Write-Verbose "Results exported to $OutFile"
	Write-Host "Exported $($Results.Count) row(s) to $OutFile"
}

$Results
