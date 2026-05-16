<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	12/31/2022 12:25 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Force-WSUSCheckin.PS1
	===========================================================================
	.DESCRIPTION
		A description of the file.

	.LINK
		https://pleasework.robbievance.net/howto-force-really-wsus-clients-to-check-in-on-demand/
#>



Function Force-WSUSCheckin($Computer) {
	Invoke-Command -computername $Computer -scriptblock { Start-Service wuauserv -Verbose }

	# Have to use psexec with the -s parameter as otherwise we receive an "Access denied" message loading the comobject
	$Cmd = '$updateSession = new-object -com "Microsoft.Update.Session";$updates=$updateSession.CreateupdateSearcher().Search($criteria).Updates'
	&amp; c:\bin\psexec.exe -s \\$Computer powershell.exe -command $Cmd

	Write-host "Waiting 10 seconds for SyncUpdates webservice to complete to add to the wuauserv queue so that it can be reported on"

	Start-sleep -seconds 10

	Invoke-Command -computername $Computer -scriptblock
	{
		# Now that the system is told it CAN report in, run every permutation of commands to actually trigger the report in operation
		wuauclt /detectnow
		(New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
		wuauclt /reportnow
		c:\windows\system32\UsoClient.exe startscan
	}
}





$updateSession = new-object -com "Microsoft.Update.Session"
$updates=$updateSession.CreateupdateSearcher().Search($criteria).Updates
wuauclt /reportnow