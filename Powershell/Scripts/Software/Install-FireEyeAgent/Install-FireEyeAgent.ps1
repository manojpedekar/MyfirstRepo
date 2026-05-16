<#
    .SYNOPSIS
        Push-installs the FireEye / xagt endpoint agent (v33.46.6) to a list
        of remote servers, with pre/post version checks and structured
        event logging.

    .DESCRIPTION
        Reads .\serverlist.txt for the target host list. For each target:
          1. Opens a remote PSSession using ADMGMT ADM credentials
             (prompted interactively).
          2. Checks installed software for an existing FireEye agent.
             If present and at or above 33.46.6, skips. If present and
             older AND $UninstallOldVersion is $true, runs the existing
             uninstaller before installing.
          3. Copies the package/FireEye/ folder to C:\temp\ on the target.
          4. Runs msiexec on the target to install
             xagtSetup_33.46.6_universal.msi.
          5. Post-install: re-checks installed software and the xagt
             service status.

        All events accumulate in $EventLog and are exported to
        ScriptLog<timestamp>.csv at the end.

    .NOTES
        REQUIREMENTS NOT IN GIT (must be staged locally before running):

          - .\serverlist.txt
              One target FQDN per line. Removed from the repo during the
              May-2026 cleanup (it contained internal hostnames from
              2021).

          - .\package\FireEye\xagtSetup_33.46.6_universal.msi
              The FireEye agent MSI binary. Removed from the repo during
              the same cleanup (large binary, should not be in source
              control). Obtain from FireEye / Trellix support portal.

        IN-REPO:
          - .\package\FireEye\agent_config.json
              The FireEye agent bootstrap configuration is checked in.
              It contains the FireEye PRODCA cert, a provisioning cert,
              and an *encrypted* provisioning private key (passphrase is
              not in this repo). Keep the file alongside this script
              when running.
#>

#Define Scriptblocks
$InstallFireeyeScriptBlock = {
	function Add-LogMessage
	{
		param (
			[Parameter(Mandatory = $false)]
			[string]$ComputerName = $env:COMPUTERNAME,
			[Parameter(Mandatory = $false)]
			[string]$Action,
			[Parameter(Mandatory = $true)]
			[string]$LogMessage
		)
		
		$props = [ordered]@{
			'DateTime' = Get-Date -Format s;
			'Name'	   = $ComputerName;
			'Action'     = $Action;
			'Message'  = $LogMessage
		}
		$obj = New-Object -TypeName PSObject -Property $props
		
		return $obj
	}
	
	$EventLog = @()

	$process = start-process msiexec.exe -ArgumentList /i, C:\temp\fireeye\xagtSetup_33.46.6_universal.msi, /qb -wait -PassThru
	if ($process.ExitCode -eq 0)
	{
		$EventLog += Add-LogMessage -Action "Install Agent" -LogMessage "FireEye Agent has been successfully installed"
	}
	else
	{
		$EventLog += Add-LogMessage -Action "Install Agent" -LogMessage "Installer exit code  $($process.ExitCode) -- Please validate this server"
	}
		
	$keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
	
	$InstalledSW = foreach ($key in $keys)
	{
		$InstalledSoftware = Get-ChildItem $key
		foreach ($obj in $InstalledSoftware)
		{
			$props = @{
				'DisplayName' = $obj.GetValue('DisplayName')
				'DisplayVersion' = $obj.GetValue('DisplayVersion');
				'UninstallString' = $obj.GetValue('UninstallString');
				'InstallDate' = $obj.GetValue('InstallDate');
				'Publisher'   = $obj.GetValue('Publisher')
			}
			$SWItem = New-Object -TypeName PSOBject -Property $props
			$SWItem
			
		}
	}
	
	$xagt = $InstalledSW | ? { $_.DisplayName -like "*fireeye*" }
	
	if ($xagt)
	{
		$EventLog += Add-LogMessage -Action "Post Install Inventory" -LogMessage "FireEye Version Installed = $($xagt.DisplayVersion)"
		
		$XAGTService = get-service xagt -ErrorAction SilentlyContinue
		
		if ($XAGTService)
		{
			$EventLog += Add-LogMessage -Action "Post Install Service Status" -LogMessage "XAGT service is $($XAGTService.Status)"
		}
		else { $EventLog += Add-LogMessage -Action "Post Install Service Status" -LogMessage "XAGT service not found" }
	}
	else
	{
		$EventLog += Add-LogMessage -Action "Post Install Inventory" -LogMessage "FireEye Not Installed"
	}
	
	#return the eventlog
	$EventLog

}

$InstalledSoftwareScriptBlock = {
	
	function Add-LogMessage
	{
		param (
			[Parameter(Mandatory = $false)]
			[string]$ComputerName = $env:COMPUTERNAME,
			[Parameter(Mandatory = $false)]
			[string]$Action,
			[Parameter(Mandatory = $true)]
			[string]$LogMessage
		)
		
		$props = [ordered]@{
			'DateTime' = Get-Date -Format s;
			'Name'	   = $ComputerName;
			'Action'     = $Action;
			'Message'  = $LogMessage
		}
		$obj = New-Object -TypeName PSObject -Property $props
		
		return $obj
	}
	
	$UninstallOldVersion = $true
	$DesiredVersion = "33.46.6"
	$EventLog = @()
	$keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
	
	$InstalledSW = foreach ($key in $keys)
	{
		$InstalledSoftware = Get-ChildItem $key
		foreach ($obj in $InstalledSoftware)
		{
			$props = @{
				'DisplayName' = $obj.GetValue('DisplayName')
				'DisplayVersion' = $obj.GetValue('DisplayVersion');
				'UninstallString' = $obj.GetValue('UninstallString');
				'InstallDate' = $obj.GetValue('InstallDate');
				'Publisher'   = $obj.GetValue('Publisher')
			}
			$SWItem = New-Object -TypeName PSOBject -Property $props
			$SWItem
			
		}
	}
	
	$xagt = $InstalledSW | ? { $_.DisplayName -like "*fireeye*" }
		
	if ($xagt)
	{
		$EventLog += Add-LogMessage -Action "Software Inventory" -LogMessage "FireEye Version Installed = $($xagt.DisplayVersion)"
		
		$XAGTService = get-service xagt -ErrorAction SilentlyContinue
		
		if ($XAGTService)
		{
			$EventLog += Add-LogMessage -Action "Service Status" -LogMessage "XAGT service is $($XAGTService.Status)"
		}else { $EventLog += Add-LogMessage -Action "Service Status" -LogMessage "XAGT service not found" }
		
		if ([version]$xagt.DisplayVersion -lt [version]$DesiredVersion)
		{
			$EventLog += Add-LogMessage -Action "Version Check" -LogMessage "Installed version $($xagt.DisplayVersion) is less than $($DesiredVersion)"
			
			If ($UninstallOldVersion -eq $true)
			{
				Add-LogMessage -Action "Software Removal" -LogMessage "Uninstall flag set, removing old version"
				
				
				$process = Start-Process -FilePath $xagt.UninstallString.Split(" ")[0] -ArgumentList $xagt.UninstallString.Split(" ")[1], /qn, /norestart -Wait -PassThru
				if ($process.ExitCode -eq 0)
				{
					$EventLog += Add-LogMessage -Action "Uninstall" -LogMessage "Version $($xagt.DisplayVersion) of $($xagt.DisplayName) has been successfully uninstalled"
					$EventLog += Add-LogMessage -Action "Notice" -LogMessage "FireEye Install Required"
				}
				else
				{
					$EventLog += Add-LogMessage -Action "Uninstall" -LogMessage "Installer exit code  $($process.ExitCode) for Version $($xagt.DisplayVersion) of $($xagt.DisplayName) -- Please validate this server"
				}
			}
			
		}
		else
		{
			$EventLog += Add-LogMessage -Action "Version Check" -LogMessage "Installed version $($xagt.DisplayVersion) is greater than or equal to $($DesiredVersion)"
			if ([version]$xagt.DisplayVersion -eq [version]$DesiredVersion){ $EventLog += Add-LogMessage -Action "Version OK" -LogMessage "Installed version $($xagt.DisplayVersion) matches desired version $($DesiredVersion)"}
			
		}
	
	}
	else
	{
		$EventLog += Add-LogMessage -Action "Software Inventory" -LogMessage "FireEye Not Installed"
		$EventLog += Add-LogMessage -Action "Notice" -LogMessage "FireEye Install Required"
	}
	
	If (!(Test-Path C:\Temp))
	{
		$EventLog += Add-LogMessage -Action "Temp Folder" -LogMessage "C:\Temp folder not present, creating folder"
		mkdir c:\temp -Force -ErrorAction SilentlyContinue
	}
		
	#return the eventlog
	$EventLog
	
}



function Add-LogMessage
{
	param (
		[Parameter(Mandatory = $false)]
		[string]$ComputerName = $env:COMPUTERNAME,
		[Parameter(Mandatory = $false)]
		[string]$Action,
		[Parameter(Mandatory = $true)]
		[string]$LogMessage
	)
	
	$props = [ordered]@{
		'DateTime' = Get-Date -Format s;
		'Name'	   = $ComputerName;
		'Action'     = $Action;
		'Message'  = $LogMessage
	}
	$obj = New-Object -TypeName PSObject -Property $props
	
	return $obj
}

#Setup Event Log
$EventLog = @()
$LogFileDate = Get-date -Format "yyyyMMddhhmmss"
$LogFileName = "ScriptLog" + $LogFileDate + ".csv"

#get the credentials needed to remote in to servers
$AdmgmtAdmCred = Get-Credential -Message "ADMGMT ADM Credentials"

# Pull list of servers from file
$targetserverList = get-content .\serverlist.txt

$i = 0
$Count = $targetserverList.count
# Main loop
Try
{
	ForEach ($targetserver in $targetserverList)
	{
		$i++
		$Completed = [math]::Round(($i/$Count)*100,2)
		
		Write-Progress -Activity "Installing XAGT -- $i of $Count -- $Completed%" -PercentComplete $Completed -Status "$targetserver - Setup PSSession"
		$EventLog += Add-LogMessage -ComputerName $targetserver -Action "Setup" -LogMessage "Establishing PSSession"
		# Create remote PS Session
		$remoteSession = New-PSSession -ComputerName $targetserver -Credential $AdmgmtAdmCred -ErrorAction Continue
		
		# Check for running process first, skip install if application is present
		Try
		{
			Write-Progress -Activity "Installing XAGT -- $i of $Count -- $Completed%" -PercentComplete $Completed -Status "$targetserver - Checking Version"
			Remove-Variable Phase1 -ErrorAction SilentlyContinue
			$EventLog += Add-LogMessage -ComputerName $targetserver -Action "Setup" -LogMessage "Checking Installed Software"
			$Phase1 = invoke-command -ScriptBlock $InstalledSoftwareScriptBlock -Session $remoteSession
			$EventLog += $Phase1
			
			if ($Phase1 | where { $_.Action -eq "Notice" })
			{
				Write-Progress -Activity "Installing XAGT -- $i of $Count -- $Completed%" -PercentComplete $Completed -Status "$targetserver - Copying Install Files"
				$EventLog += Add-LogMessage -ComputerName $targetserver -Action "Install Agent" -LogMessage "New FireEye Agent needs to be installed - Copying Install Files"
				$sourceFolder = ".\package\FireEye\"
				$destinationFolder = "c:\temp\"
				
				if (Test-Path \\$targetserver\c$\Temp)
				{
					Copy-Item -Path $sourceFolder -Destination \\$targetserver\c$\Temp\ -Recurse
				}
				else
				{
					Copy-Item -Path $sourceFolder -Destination $destinationFolder -ToSession $remoteSession -Force -Recurse
				}
				
				$EventLog += Add-LogMessage -ComputerName $targetserver -Action "Install Agent" -LogMessage "New FireEye Agent needs to be installed - Installing Software"
				Write-Progress -Activity "Installing XAGT -- $i of $Count -- $Completed%" -PercentComplete $Completed -Status "$targetserver - Installing FireEye"
				$InstallPhase = invoke-command -ScriptBlock $InstallFireeyeScriptBlock -Session $remoteSession
				$EventLog += $InstallPhase
			}

			
		}
		catch
		{
			Write-Host $ErrorMessage
			$EventLog += Add-LogMessage -ComputerName $targetserver -Action "ERROR" -LogMessage "Failed to Connect to PSSession"
		}
	}
}
catch
{
	Write-Host $ErrorMessage
	write-host $FailedItem
}

$EventLog | Export-Csv $LogFileName -NoTypeInformation
$EventLog | ft -AutoSize
