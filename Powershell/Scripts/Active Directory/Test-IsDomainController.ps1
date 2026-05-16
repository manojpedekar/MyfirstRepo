
Function Test-IsDomainController {
	<#
	.SYNOPSIS
	    Checks if the computer is a Domain Controller.

	.DESCRIPTION
	    This function uses WMI to determine if the current computer is a Domain Controller by checking its DomainRole.
	    It returns True if the computer is a Primary Domain Controller (PDC) or Backup Domain Controller (BDC),
	    and False otherwise.

	.EXAMPLE
	    PS> Test-IsDomainController
	    This example checks if the current computer is a Domain Controller and returns True or False.

	.NOTES
	    Author: Pete Demers
	    Version: 1.0
	
	DomainRole Property Values:
		0 - Standalone Workstation
		1 - Member Workstation
		2 - Standalone Server
		3 - Member Server
		4 - Primary Domain Controller
		5 - Backup Domain Controller
	#>
	
	[CmdletBinding()]
	Param ()
	
	Try {
		# Query WMI for the role of the computer
		$computerRole = Get-WmiObject Win32_ComputerSystem -Property DomainRole | Select-Object -ExpandProperty DomainRole
		
		# DomainRole values: 4 (Primary Domain Controller), 5 (Backup Domain Controller)
		If ($computerRole -in (4,5)) {
			Return $true
		} Else {
			Return $false
		}
	} Catch {
		Write-Error "An error occurred while checking the domain role: $_"
		Return $false
	}
}
