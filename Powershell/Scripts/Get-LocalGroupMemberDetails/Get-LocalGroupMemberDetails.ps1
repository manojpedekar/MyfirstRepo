


function Get-LocalGroupMemberDetailsV2
{
	<#
	.SYNOPSIS
		Example of getting local group members using PSv2 with ADSI
	
	.DESCRIPTION
		A detailed description of the Get-LocalGroupMemberDetailsV2 function.
	
	.PARAMETER Computer
		The computer name to quety.  Local computer name is the default value.
	
	.EXAMPLE
		PS C:\> Get-LocalGroupMemberDetailsV2

    .EXAMPLE
	    PS C:\> Get-LocalGroupMemberDetailsV2 -Computer DSKCUTIL02

	.NOTES
		Script created using the capibilities of PS v2 in order to support all possible configurations in the SS&C Environments.
    #>
	
	[CmdletBinding()]
	param
	(
		[String]$Computer = $env:COMPUTERNAME
	)
	
	$LocalADSI = [ADSI]"WinNT://$Computer"
	
	$LocalGroups = $LocalADSI.psbase.children | where { $_.psbase.schemaClassName -eq 'group' }
	
	foreach ($LocalGroup in $LocalGroups)
	{
		$LocalGroupName = $LocalGroup.name[0]
		
		$group = [ADSI]$LocalGroup.psbase.Path
		$GroupMembers = $group.psbase.Invoke("Members")
		
		foreach ($GroupMember in $GroupMembers)
		{
			$props = @{
				'ComputerName' = $Computer;
				'LocalGroup'   = $LocalGroupName;
				'Member'	   = $GroupMember.GetType().InvokeMember("Name", 'GetProperty', $null, $GroupMember, $null);
				'Type'		   = $GroupMember.GetType().InvokeMember("Class", 'GetProperty', $Null, $GroupMember, $Null);
				'Path'		   = $GroupMember.GetType().InvokeMember("ADsPath", 'GetProperty', $Null, $GroupMember, $Null)
			}
			$obj = New-Object -TypeName PSOBject -Property $props
			Write-Output $obj
		}
	}
}

