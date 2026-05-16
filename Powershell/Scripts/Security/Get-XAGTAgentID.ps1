<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	9/13/2022 2:12 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Get-XAGTAgentID.ps1
	===========================================================================
	.DESCRIPTION
		This script is designed to return the XAGT Agent ID 
#>


$LogFile = "C:\temp\xagt.log"

# Test Path to determine where fireeye is installed and export logs
if (Test-Path 'C:\Program Files (x86)\FireEye\xagt\xagt.exe')
{
	& 'C:\Program Files (x86)\FireEye\xagt\xagt.exe' -g $LogFile | Out-Null
}
elseif (Test-Path 'C:\Program Files\FireEye\xagt\xagt.exe')
{
	& 'C:\Program Files\FireEye\xagt\xagt.exe' -g $LogFile | Out-Null
}
else
{
	return "FireEye Missing"
}

#Import the log data and get the first line that has the agent ID
$data = Get-Content $LogFile | ? { $_ -like '* aid *' } | select -first 1

# Clean Up the log file.  This needs to be before the return statement
try { Remove-Item $LogFile -Confirm:$False }
catch { $Error }

# Return the agent ID
return $data.substring($data.length - 23, 22)
