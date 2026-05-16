<#
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	10/29/2022 8:36 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.

Goals:

1. Read the value of the WSUS server from the registry
2. Test connection to the wsus server
3. Get the status of the Windows Update service (wuauserv)
4. check proxy settings
5. get network info
       - IP, Subnet
6. Works on all systems between .Net 2.0 and .Net 7

#>

$scriptBlockCode = {
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
		
		if ($psversiontable.psversion.major -gt 2)
		{
			$portOpened = $tcpClient.ConnectAsync($WSUSServer, $WSUSPort).Wait($Timeout)
		}
		else
		{
			$tcpclient.receivetimeout = $Timeout
			$tcpClient.Connect($WSUSServer, $WSUSPort)
			$PortOpened = $tcpclient.connected
		}
		#will return a T/F
	}
	$WSUSService = Get-Service wuauserv
	
	If (Test-CommandExists -command Get-CimInstance) {
		$netinfo = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object {$_.IPENABLED -eq 'true'	}
	} Else {
		$netinfo = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPENABLED -eq 'true' }
	}
	
	$ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
	
	$report = New-Object psobject
	Add-Member -MemberType NoteProperty -name Domain -Value $ComputerSystem.Domain -InputObject $report
	Add-Member -MemberType NoteProperty -name Server-Name -Value $ComputerSystem.Name -InputObject $report
	Add-Member -MemberType NoteProperty -name WSUS-Server -Value $WSUSSERVER -InputObject $report
	Add-Member -MemberType NoteProperty -name WSUSPort -Value $WSUSPort -InputObject $report
	Add-Member -MemberType NoteProperty -name Connected -Value $PortOpened -InputObject $report
	write-output $report
	
	
}



$Servers = Get-Content C:\Temp\servers.txt

Invoke-Command -ComputerName $Servers -ScriptBlock $scriptBlockCode

