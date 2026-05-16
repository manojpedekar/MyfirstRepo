$EventLog = @()

Import-Module GroupPolicy

$PossiblePaths = @(
	"C:\Windows\SysVol\Domain\Policies",
	"C:\Windows\SYSVOL_DFSR\domain\Policies",
	"E:\Windows\SYSVOL\domain\Policies",
	"E:\Windows\SYSVOL_DFSR\domain\Policies"
)

foreach ($PossiblePath in $PossiblePaths)
{
	If (Test-path $possiblePath)
	{
		$SysvolPath = $PossiblePath
	}
}

$AllGpos = Get-GPO -all -Server $env:COMPUTERNAME
$GpoInfo = foreach ($g in $AllGpos)
{
	[xml]$Gpo = Get-GPOReport -ReportType Xml -Guid $g.Id
	[PSCustomObject]@{
		"DC" = $env:COMPUTERNAME
		"Name" = $Gpo.GPO.Name
		"GUID" = $g.id
		"Comp-Ad-Ver" = $Gpo.GPO.Computer.VersionDirectory
		"Comp-Sys-Ver" = $Gpo.GPO.Computer.VersionSysvol
		"Comp Enabled?" = $Gpo.GPO.Computer.Enabled
		"User-Ad-Ver" = $Gpo.GPO.User.VersionDirectory
		"User-Sys-Ver" = $Gpo.GPO.User.VersionSysvol
		#"ACL Match" = $gpo.IsAclConsistent()
		"User Enabled?" = $Gpo.GPO.User.Enabled
		
	}
}
#$GpoInfo | Sort-Object Name | Format-Table -AutoSize -Wrap
$GpoInfo | Sort-Object Name | Export-Csv -Path E:\GPO\GPOHealth\$($env:COMPUTERNAME)_GpoHealth.csv -NoTypeInformation

$GroupPolicies = Get-ChildItem $SysvolPath

$ErrorActionPreference = 'SilentlyContinue'

Foreach ($Policy in $GroupPolicies)
{
	$results = icacls $Policy.FullName
	
	if ($results)
	{
		#This command will remove the trailing 2 lines from the icacls command and then trim the whitespace
		#This leaves us with a list that we can group to dtermin if there are any duplicates
		$ACLCount = $results | select -first (($results | measure).count - 2) | % { $_.replace($($Policy.fullname), '').trim() } | group | ? { $_.count -gt 1 }
		
		#We test the $ACLCount to see if there are any results.  There are we wll dipsplay the results
		if ($ACLCount) { $EventLog += [PSCustomObject]@{
				"DC"   = $env:COMPUTERNAME
				"GPO_GUID" = $Gpo.GPO.Name
				"Message" = "Duplicate Domain Admin ACLs"
			}
		}
	}
	else { $EventLog += $EventLog += [PSCustomObject]@{
			"DC"	   = $env:COMPUTERNAME
			"GPO_GUID" = $Gpo.GPO.Name
			"Message"  = "Error Accessing ACLs"
		}
	}
	
}

$EventLog | Export-Csv -Path E:\GPO\GPOHealth\$($env:COMPUTERNAME)_DuplicateACLs.csv -NoTypeInformation