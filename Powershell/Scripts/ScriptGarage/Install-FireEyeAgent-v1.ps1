<#
    FROZEN HISTORICAL RECORD. Earlier (v1) version of the FireEye agent
    rollout, targeting xagtSetup_32.30.13_universal.msi. Superseded by
    Powershell/Scripts/Software/Install-FireEyeAgent/Install-FireEyeAgent.ps1
    (v2, targets 33.46.6) which has version comparison, optional
    uninstall-of-older-version, and structured event logging.

    Kept as historical reference for the v1 rollout approach (simpler:
    transcript-based logging, no version compare, copies the whole
    .\package directory rather than just package/FireEye/).

    Original filename was install-msipacakage.ps1 (typo). Dependencies
    referenced by the script (serverlist.txt, xagtSetup MSI, Logs/
    directory) were removed from the repo during the May-2026 cleanup.
#>

function Get-InstalledApps {
    # Pulled from https://github.com/gangstanthony/PowerShell/blob/master/Get-InstalledApps.ps1
    param (
        [Parameter(ValueFromPipeline=$true)]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [string]$NameRegex = ''
    )
    
    foreach ($comp in $ComputerName) {
        $keys = '','\Wow6432Node'
        foreach ($key in $keys) {
            try {
                $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $comp)
                $apps = $reg.OpenSubKey("SOFTWARE$key\Microsoft\Windows\CurrentVersion\Uninstall").GetSubKeyNames()
            } catch {
                continue
            }

            foreach ($app in $apps) {
                $program = $reg.OpenSubKey("SOFTWARE$key\Microsoft\Windows\CurrentVersion\Uninstall\$app")
                $name = $program.GetValue('DisplayName')
                if ($name -and $name -match $NameRegex) {
                    [pscustomobject]@{
                        ComputerName = $comp
                        DisplayName = $name
                        DisplayVersion = $program.GetValue('DisplayVersion')
                        Publisher = $program.GetValue('Publisher')
                        InstallDate = $program.GetValue('InstallDate')
                        UninstallString = $program.GetValue('UninstallString')
                        Bits = $(if ($key -eq '\Wow6432Node') {'64'} else {'32'})
                        Path = $program.name
                    }
                }
            }
        }
    }
}

# Set Log File and start transcript
$filedate = Get-date -Format "yyyyMMddhhmmss"
$filename = "ScriptLog" + $filedate + ".txt"
start-transcript -Path ".\Logs\$filename" -NoClobber


# Get credentials
$NormUsrName = Read-Host "Enter priviledged username"
Try {
    $admgmt = "admgmt.ssncad.global"
    $AdmgmtAdmUsr = $NormUsrName
    $AdmgmtAdmCred = Get-Credential $AdmgmtAdmUsr -Message "ADMGMT ADM Credentials" 
    #$DomainObj = Get-ADDomain -Server $admgmt -Credential $AdmgmtAdmCred -ErrorAction SilentlyContinue
    #Write-Host "ADM credentials validated" -ForegroundColor Green
} catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    Write-Warning $ErrorMessage
    Write-Warning $FailedItem
}

#Define Scriptblocks

$InstalledSoftwareScriptBlock = {
	
	$keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
	
	foreach ($key in $keys)
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
}

# Pull list of servers from file
$targetserverList = get-content .\serverlist.txt
#Write-host $targetserverList
Write-Verbose "Before Loop (get-date)"

# Main loop
Try {
    ForEach ($targetserver in $targetserverList) {
		# Create remote PS Session
		
        $remoteSession = New-PSSession -ComputerName $targetserver -Credential $AdmgmtAdmCred

        # Check for running process first, skip install if application is present
        Try {
            $checkresult = Invoke-Command -Session $remoteSession -ScriptBlock {Get-Process}
            if ($checkresult -like "*xagt*") {
                Write-Host "Fireeye process found running on" $targetserver
                $installedApps = invoke-command -ScriptBlock $InstalledSoftwareScriptBlock -Session $remoteSession
				$installedApps | ? { $_.DisplayName -like "*fireeye*" }
				
            } else {
                # Copy package files to remote server
                $sourceFolder = ".\package"
                $destinationFolder = "c:\temp\fireeye"
				$packageContents = Get-ChildItem $sourceFolder -Name
				Invoke-Command -Session $remoteSession -ScriptBlock { New-Item -Path $args[0] -Type Directory -Force } -ArgumentList $destinationFolder
                ForEach ($packageItem in $packageContents) {
                    $fullSoure = $sourceFolder + "\" + $packageItem
                    # Force create destination folder
                    Copy-Item -Path $fullSoure -Destination $destinationFolder -ToSession $remoteSession -Force
                }
                #Invoke-Command -Session $remoteSession -ScriptBlock {Get-ChildItem -Path $args[0]} -ArgumentList $destinationFolder

                # Issue command to install software
                Invoke-command -Session $remoteSession -ScriptBlock {start-process msiexec -ArgumentList '/i C:\temp\fireeye\xagtSetup_32.30.13_universal.msi /qn' -wait}

                # Validate software is running
                $postinstallresult = Invoke-Command -Session $remoteSession -ScriptBlock {Get-Process}
                if ($postinstallresult -like "*xagt*") {
                    Write-Host "Fireeye process found running on" $targetserver
					$installedApps = invoke-command -ScriptBlock $InstalledSoftwareScriptBlock -Session $remoteSession
					$installedApps | ? { $_.DisplayName -like "*fireeye*" }
				}
				else
				{
					Write-Host "Fireeye is not running."
					# Write-Host $postinstallresult
					# Invoke-Script -Session $remoteSession -Scriptblock {Get-ItemProperty -path: HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Format-Table -AutoSize
					$installedApps = invoke-command -ScriptBlock $InstalledSoftwareScriptBlock -Session $remoteSession
					$installedApps | ? { $_.DisplayName -like "*fireeye*" }
				}
			}
		}
		catch
		{
			Write-host $ErrorMessage
		}
	}
}
catch
{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	Write-Host $ErrorMessage
	Write-Host $FailedItem
}

# Turn off transcript
Stop-Transcript