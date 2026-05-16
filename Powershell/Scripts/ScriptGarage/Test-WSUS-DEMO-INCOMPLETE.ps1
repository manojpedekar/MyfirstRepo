<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	10/24/2022 4:49 PM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



<#

Goals:

1. Read the value of the WSUS server from the registry
2. Test connection to the wsus server
3. Get the status of the Windows Update service (wuauserv)
4. check proxy settings
5. get network info
	- IP, Subnet

Between .Net 2.0 and .Net 7

#>

$scriptBlockCode= {
	#===============================================================================
	# Script Functions
	#===============================================================================
	
	Function Test-CommandExists
	{
		# Simple function to test for a powershell command
		Param ($command)
		$oldPreference = $ErrorActionPreference
		$ErrorActionPreference = 'stop'
		
		try { if (Get-Command $command) { $true } }
		Catch { $false }
		Finally { $ErrorActionPreference = $oldPreference }
	}
	
	Remove-Variable WSUS -ErrorAction SilentlyContinue
	$WSUS = (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate).WUServer
	if ($WSUS)
	{
		$WSUSServer = $WSUS.Substring($WSUS.LastIndexOf("//") + 2, $WSUS.LastIndexOf(":") - ($WSUS.LastIndexOf("//")) - 2)
		$WSUSPort = $WSUS.Substring($WSUS.LastIndexOf(":") + 1, $WSUS.length - $WSUS.LastIndexOf(":") - 1)
		
		$Timeout = 1000
		$tcpClient = New-Object System.Net.Sockets.TcpClient
		$portOpened = $tcpClient.ConnectAsync($WSUSServer, $WSUSPort).Wait($Timeout) #will return a T/F
	}
	$WSUSService = Get-Service wuauserv
	
	if (Test-CommandExists -command Get-CimInstance)	{
		$netinfo = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | ? { $_.IPENABLED -eq 'true' }
	} else { $netinfo = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter { IPENABLED = 'true' } }
	
	
	
}













$Servers = Get-Content C:\Temp\servers.txt

$WSUSRESULTS = Invoke-Command -ComputerName $Servers -ScriptBlock $scriptBlockCode



Invoke-Command -Session 






























ForEach ($Server in $Servers)
{
	#enter-pssession -Computername $Server
	$WSUS = Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
	$NetStatPort = netstat -an | findstr 8530* #<-- this is not going to get you what you want
	$ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
	
	
	$report = New-Object psobject
	$report | Add-Member -MemberType NoteProperty -name Server-FQDN -Value $Server
	$report | Add-Member -MemberType NoteProperty -name Domain -Value $ComputerSystem.Domain
	$report | Add-Member -MemberType NoteProperty -name Server-Name -Value $ComputerSystem.Name
	$report | Add-Member -MemberType NoteProperty -name WSUS-Server -Value $WSUS.WUServer
	$report | Add-Member -MemberType NoteProperty -name NetStat -Value $NetStatPort
	
	$report | export-csv C:\temp\wsus-test.csv -Append -NoTypeInformation
	
	#exit-pssession
}

