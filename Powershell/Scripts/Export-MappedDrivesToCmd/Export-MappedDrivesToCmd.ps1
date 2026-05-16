<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	10/4/2023 7:51 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Export-MappedDrivesToCmd 
	 Version:		1.0
	===========================================================================
	.DESCRIPTION
		Export currently mapped drives to a CMD file and sends email status
#>


##################################################
#                 FUNCTIONS                      #
##################################################

Function Get-HomeUNCPath {
<#
	.SYNOPSIS
		Returns the UNC for the users HOMESHARE
	
	.DESCRIPTION
		Returns UNC for users home share.  If not defined, returns false
	
	.EXAMPLE
				PS C:\> Get-HomeUNCPath
	
	.NOTES
		Version 1.0
        Created by dt234083
        Created on 10/04/2023
#>
	
	$homeShare = [Environment]::GetEnvironmentVariable("HOMESHARE")
	
	If (-not [string]::IsNullOrEmpty($homeShare)) {
		Return $homeShare
	} Else {
		Return $false
	}
}

Function Test-WriteToHomeShare {
<#
	.SYNOPSIS
		Validates write access to users HOMESHARE
	
	.DESCRIPTION
		Validates write access to users HOMESHARE
	
	.PARAMETER UNCPath
		Path to users HOMESHARE
	
	.EXAMPLE
				PS C:\> Test-WriteToHomeShare -UNCPath $ENV:HOMESHARE
	
	.NOTES
		Version 1.0
        Created by dt234083
        Created on 10/04/2023
#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$UNCPath
	)
	
	$testFilePath = Join-Path $UNCPath "test_write_file.tmp"
	
	Try {
		# Attempt to write a test file using .NET
		[System.IO.File]::WriteAllText($testFilePath, "Test Write")
		
		# If written successfully, remove the test file and return $true
		[System.IO.File]::Delete($testFilePath)
		Return $true
	} Catch {
		# If any error occurs, return $false without displaying the error
		Return $false
	}
}

Function Export-MappedDrivesToCmd {
<#
	.SYNOPSIS
		Creates mapped drive script using currently mapped drives
	
	.DESCRIPTION
		Creates mapped drive script using currently mapped drives
	
	.PARAMETER OutputFile
		File name for exported mapped drive script
	
	.EXAMPLE
		PS C:\> Export-MappedDrivesToCmd -OutputFile remapDrives.cmd
	
	.NOTES
		Version 1.0
		Created by dt234083
		Created on 10/04/2023
#>
	
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$OutputFile
	)
	
	$mappedDrives = Get-WmiObject -Class Win32_NetworkConnection
	
	If (-not $mappedDrives) {
		$ErrorSubjectLine = "$($env:USERNAME) - No mapped drives to record"
		Send-ErrorEmail -subject $ErrorSubjectLine
		exit 1
	}
	
	ForEach ($drive In $mappedDrives) {
		$driveLetter = $drive.LocalName
		$networkPath = $drive.RemoteName
		
		$cmdLine = "net use $driveLetter $networkPath /PERSISTENT:YES"
		Add-Content -Path $OutputFile -Value $cmdLine
	}
	
	#Write-Host "CMD file created at $OutputFile"
	$ErrorSubjectLine = "$($env:USERNAME) - Script Created Successfully"
	Send-ErrorEmail -subject $ErrorSubjectLine
}

Function Send-ErrorEmail {
	Param (
		[Parameter(Mandatory = $true)]
		[string]$mailHost, ### Need the SMTP Mail host defined
		[Parameter(Mandatory = $true)]
		[string]$toAddress = "user@domain.dom",
		[Parameter(Mandatory = $true)]
		[string]$fromAddress = "ExportMappedDrives@sscinc.com",
		[Parameter(Mandatory = $true)]
		[string]$subject = "Error occurred creating logon drive script"
	)
	
	#if we want to change to an array of stings:
	#[string[]]$toAddresses = @("user1@domain.dom", "user2@domain.dom"),
			
	Try {
		$smtpClient = New-Object System.Net.Mail.SmtpClient
		$smtpClient.Host = $mailHost
		
		$mailMessage = New-Object System.Net.Mail.MailMessage
		$mailMessage.From = $fromAddress
		$mailMessage.To.Add($toAddress)
		#$toAddresses | ForEach-Object { $mailMessage.To.Add($_) }  #use this if we change over to an array of strings
		$mailMessage.Subject = $subject
		$mailMessage.Body = "An error occurred while creating the logon drive script. Please check the system."
		
		$smtpClient.Send($mailMessage)
		Write-Host "Email sent successfully."
	} Catch {
		Write-Error "Failed to send email. Error: $_"
	}
}

##################################################
#                MAIN SCRIPT                     #
##################################################

$OutputFile = "remapDrives.cmd"
$homeUNC = Get-HomeUNCPath

If (-not $homeUNC) {
	$ErrorSubjectLine = "$($env:USERNAME) - HOMESHARE not found"
	Send-ErrorEmail -subject $ErrorSubjectLine
	exit 1
}

If (-not (Test-WriteToHomeShare -UNCPath $homeUNC)) {
	$ErrorSubjectLine = "$($env:USERNAME) - Write Access to $($homeUNC) failed"
	Send-ErrorEmail -subject $ErrorSubjectLine
	Exit 1
}

$CompletePath = Join-Path -Path $homeUNC -ChildPath $OutputFile

Try {
	If (Test-Path $CompletePath) {
		# File exists, delete without prompting
		Remove-Item -Path $CompletePath -Force -ErrorAction Stop
	}
} Catch {
	$ErrorSubjectLine = "$($env:USERNAME) - Delete old file failed on $($homeUNC)"
	# Handle the error or send an email with the $ErrorSubjectLine, etc.
	Write-Error $ErrorSubjectLine
	Exit 1
}

Export-MappedDrivesToCmd -OutputFile $CompletePath
