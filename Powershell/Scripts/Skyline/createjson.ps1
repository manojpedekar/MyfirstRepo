<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/21/2023 6:57 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

$WCDServers = @('WCDSKYAWRXA001',
'WCDSKYCPMGXA001',
'YKTSKYMCRXA001',
'WCDSKYCPRXA001',
'WCDSKYBLCPXA001'
)

$tfdWCD = @'
resource "ssccloud_instance" "###REPLACEME###" {
  name = "###REPLACEME###"
  image = data.ssccloud_image.w2k19.id
  project = "project-de361c84-3fee-491f-afe2-761bd6642dd6"
  subproject = "subproject-44054efc-20d8-4cc8-8f61-8a76c59aea0a"
  deployment_zone = "deploymentzone-na-central-kc"
  size = "nano.c2.m8"
  tier_name = "Application"
  domain_delegation  = "sscclient01.ssncad.global"
  tags = {
    Client = "SKYLINEProduction"
    Domain = "sscclient01.ssncad.global"
    Purpose = "Kansas City Skyline Server # 1"
  }

}
'@

Clear-Host; $WCDServers | ForEach-Object { $tfdWCD.Replace("###REPLACEME###", $_) }




$tfdykt = @'
resource "ssccloud_instance" "###REPLACEME###" {
  name = "###REPLACEME###"
  image = data.ssccloud_image.w2k19.id
  project = "project-de361c84-3fee-491f-afe2-761bd6642dd6"
  subproject = "subproject-44054efc-20d8-4cc8-8f61-8a76c59aea0a"
  deployment_zone = "deploymentzone-na-east-ykt"
  size = "nano.c2.m8"
  tier_name = "Application"
  domain_delegation  = "sscclient01.ssncad.global"
  tags = {
    Client = "SKYLINEProduction"
    Domain = "sscclient01.ssncad.global"
    Purpose = "Kansas City Skyline Server # 1"
  }

}
'@

Clear-Host; $YKTServers | ForEach-Object { $tfd.Replace("###REPLACEME###", $_) }







Function getdeploystats {
	
	$results = Get-CloudInstances -APIKey $apikey -projectId "project-de361c84-3fee-491f-afe2-761bd6642dd6"
	
	$totalResults = $results | Select-Object -ExpandProperty content | Select-Object name, id, tasksStatus, deploymentzoneid, DNS, @{ N = 'MinionID'; E= {$_.dns.replace("ssnc-corp.cloud", "sscclient01.ssncad.global") } }
	$FilteredResults = $results | Select-Object -ExpandProperty content | Where-Object { $_.tasksStatus -eq "COMPLETED" -and ($_.Name -like 'ykt*' -or $_.Name -like 'wcd*') } | Select-Object name, id, tasksStatus, deploymentzoneid
	
	$results | Format-Table -AutoSize
	
	$totalResults | Select-Object name, id, tasksStatus, deploymentzoneid | Format-Table -AutoSize
	
	$totalResults | Group-Object tasksStatus | Select-Object count, Name
	
	
	$totalResults | export-csv .\currentstatus.csv -NoTypeInformation
	Write-Host (get-date)
	
}






$volume = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'database' -and $_.Size -gt 49GB -and $_.Size -lt 51GB }
If ($volume.count -eq 1) {
	$driveLetter = $volume.DriveLetter
	Get-Partition -DriveLetter $driveLetter | Set-Partition -NewDriveLetter X
}

