Function Test-PendingReboot {
	
	# Initialize a PS Object to track reasons for a pending reboot
	$rebootRequired = New-Object PSObject -Property @{
		RebootPending			    = $false
		AutoUpdateKey			    = $false
		ComponentBasedServicingKey  = $false
		UpdatesKey				    = $false
		PendingFileRenameOperations = $false
		SCCMRebootManagement	    = $false
	}
	
	# Define variables for registry paths and file locations using custom objects instead of a CSV conversion
	$registryPaths = @(
		@{ Property = "AutoUpdateKey"; Key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"; RegKey = "Exists" },
		@{ Property = "ComponentBasedServicingKey"; Key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"; RegKey = "Exists" },
		@{ Property = "UpdatesKey"; Key = "HKLM:\SOFTWARE\Microsoft\Updates"; RegKey = "RebootRequired"; RebootValue = 1},
		@{ Property = "SCCMRebootManagement"; Key = "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData"; RegKey = "RebootRequired"; RebootValue = 1 }
	)
	
	$pendingFileRenamePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
	
	# Check for RebootRequired keys
	ForEach ($path In $registryPaths) {
		If (Test-Path $path.Key) {
			#Write-Host "Reboot required due to updates at: $($path.Key)"
			$rebootRequired.RebootPending = $true
			$rebootRequired[$path.Property] = $true
		}
	}
	
	# Check for pending file rename operations
	If ((Get-ItemProperty -Path $pendingFileRenamePath -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations) {
		#Write-Host "Reboot required due to pending file rename operations."
		$rebootRequired.RebootPending = $true
		$rebootRequired.PendingFileRenameOperations = $true
	}
	
	# Check for SCCM client reboot marker specifically for RebootRequired
	$ccmRebootPath = "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData"
	$rebootRequiredKey = "RebootRequired"
	If (Test-Path $ccmRebootPath) {
		# Check for the specific RebootRequired value
		$rebootRequiredValue = Get-ItemProperty -Path $ccmRebootPath -Name $rebootRequiredKey -ErrorAction SilentlyContinue
		
		# If the RebootRequired key exists and is set to true, set RebootPending to true
		If ($rebootRequiredValue -and $rebootRequiredValue.RebootRequired -eq 1) {
			Write-Host "Reboot required due to SCCM client operations."
			$rebootRequired.RebootPending = $true
			$rebootRequired.SCCMRebootManagement = $true
		}
	}
	
	# Return the result
	Return $rebootRequired
}

