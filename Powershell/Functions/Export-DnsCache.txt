
Function Log-Message {
	
	<#
	.SYNOPSIS
	    Logs a message to both the console and a specified log file.
	.DESCRIPTION
	    The Log-Message function writes a message with a timestamp to the standard output and appends the same message to a log file. It checks if the directory for the log file exists and creates it if necessary.
	.PARAMETER message
	    The message text to log. This parameter is required.
	.PARAMETER filePath
	    The path to the log file where the message will be appended. Defaults to 'C:\temp\automationlog.log'.
	.EXAMPLE
	    Log-Message -Message "Process completed successfully"
	    Logs the message with a timestamp to the console and to 'C:\temp\automationlog.log'.
	.EXAMPLE
	    Log-Message -Message "User logged in" -filePath "C:\logs\userlog.log"
	    Logs the message to the console and to a specified file path.
	.NOTES
	    This function requires that the user has the necessary permissions to create directories and write to files in the specified paths.
	#>
	
	Param (
		[Parameter(Mandatory = $true)]
		[string]$Message,
		[string]$filePath = "C:\temp\automationlog.log"
	)
	$timestamp = [datetime]::Now
	$logEntry = "$timestamp : $message"
	
	# Ensure the directory exists
	$dir = Split-Path -Path $filePath
	If (-not (Test-Path -Path $dir)) {
		Try {
			New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
		} Catch {
			Write-Error "Failed to create directory '$dir': $_"
			Return # Exit the function if the directory cannot be created
		}
	}
	
	# Try to write to the log file
	Try {
		Add-Content -Path $filePath -Value $logEntry -ErrorAction Stop
	} Catch {
		Write-Error "Failed to write to log file: $_"
	}
}

Function Export-DnsCache {
	<#
	.SYNOPSIS
	    Dumps the DNS cache to a log file with a unique timestamped filename to avoid file collisions.

	.DESCRIPTION
	    The Export-DnsCache function retrieves the current DNS client cache and exports it to an XML file. 
	    The file is saved to a specified directory, and a timestamp is included in the filename to ensure 
	    each file is unique.

	.PARAMETER logFilePath
	    The directory path where the DNS cache file will be saved. Defaults to "C:\path\to\output\".

	.EXAMPLE
	    Export-DnsCache -logFilePath "C:\Logs\DNSCache\"
	    Dumps the DNS cache to a new XML file in the specified directory.

	.EXAMPLE
	    Export-DnsCache
	    Dumps the DNS cache to the default directory ("C:\path\to\output\") with a timestamped filename.

	.OUTPUTS
	    System.String
	    Returns the full path of the generated DNS cache log file.

	.NOTES
	    This function requires administrative privileges to access DNS client cache information.
	#>
	
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $false)]
		[string]$logFilePath = "C:\Temp\"
	)
	
	$FN = $MyInvocation.MyCommand.Name
	Log-Message -Message "**** Starting $FN Function ****"
	
	# Set up the log file path with a timestamp
	$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
	$logFilePath = Join-Path -Path $logFilePath -ChildPath "dnscache_$timestamp.xml"
	
	# Validate that the directory exists, creating it if necessary
	If (!(Test-Path -Path $logFilePath)) {
		Try {
			New-Item -ItemType Directory -Path $logFilePath -Force | Out-Null
		} Catch {
			Log-Message -Message "Failed to create directory: $logFilePath. $_"
			Return
		}
	}

	# Dump the DNS cache to the log file
	Try {
		Get-DnsClientCache | Export-Clixml -Path $logFilePath -Force
		Log-Message -Message "DNS cache dumped to: $logFilePath"
	} Catch {
		Log-Message -Message "Failed to dump DNS cache: $_"
	}
	
	Log-Message -Message "**** Ending $FN Function ****"
}
