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
Clear-Host
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

				if ($psversiontable.psversion.major -gt 2){
					$portOpened = $tcpClient.ConnectAsync($WSUSServer, $WSUSPort).Wait($Timeout)
					}else {
					$tcpclient.receivetimeout = $Timeout 
					$tcpClient.Connect($WSUSServer, $WSUSPort)
					$PortOpened = $tcpclient.connected
				}
			  #will return a T/F
       }
       $WSUSService = Get-Service wuauserv
	   $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
	   $WUAgentVersion = (Get-ItemProperty -Path 'C:\Windows\System32\wuaueng.dll').VersionInfo.productversion
       
       if (Test-CommandExists -command Get-CimInstance)
       {
              $netinfo = Get-CimInstance -computername $ComputerSystem.Name -ClassName Win32_NetworkAdapterConfiguration | ? { $_.IPENABLED -eq 'true' }
			  $OSData = (Get-CimInstance -ClassName CIM_OperatingSystem)

       }
       else { $netinfo = Get-WmiObject -computername $ComputerSystem.Name -Class Win32_NetworkAdapterConfiguration | ? { $_.IPENABLED -eq 'true' }
			  $OSData = (Get-WMIObject win32_operatingsystem)

	   }
       $IP = $netinfo.ipaddress[0]
       $DG = $netinfo.defaultipgateway[0]


         
       $hash = @{
       DomainName         = $ComputerSystem.Domain
       ServerName         = $ComputerSystem.Name
	   OSName             = $OSData.Name
	   OSVersion          = $OSData.Version
	   OSArchitecture     = $OSData.OSArchitecture
	   ServerManufacturer = $ComputerSystem.Manufacturer
	   ServerModel        = $ComputerSystem.Model
	   IPAddress          = $IP
	   DefaultGateway     = $DG
       WSUSServer         = $WSUSSERVER
       WSUSPort           = $WSUSPort
	   WUAgentVersion     = $WUAgentVersion
	   Connected          = $PortOpened

    }
        
    $Object += New-Object PSObject -Property $hash | Select-Object "ServerName", "DomainName"  
    $Object | Export-Csv C:\Temp\Mark-test.csv -NoTypeInformation -Append    

}



$Servers = Get-Content C:\Temp\servers-BF.txt

        foreach($server in $servers){

            Invoke-Command -ComputerName $Server -ScriptBlock $scriptBlockCode

           
      
          
    

                 }
 