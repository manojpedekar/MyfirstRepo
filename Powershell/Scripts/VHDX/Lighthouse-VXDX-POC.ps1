<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	3/11/2025 2:03 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>
Function Get-IsAdministrator {
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
    $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

Function Get-IsUacEnabled {
    (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System).EnableLua -ne 0
}

Function Test-VHDXMounted {
    Param (
        [string]$VHDXPath
    )
    
    $vhdMounted = Get-Disk | Where-Object { $_.location -eq $VHDXPath }
    
    If ($vhdMounted) {
        return $true
    }
    
    return $false
    
}

Function Get-CurrentADSite {
    <#
    .SYNOPSIS
    Gets the current Active Directory site for the computer where the script is run.

    .DESCRIPTION
    The Get-CurrentADSite function retrieves the Active Directory site associated with the computer on which it is executed. It uses .NET classes to interact with Active Directory and obtain the site information. If the computer is not associated with a site, or if the function encounters any issues in determining the site, it returns "Not Defined".

    .PARAMETER None
    This function does not take any parameters.

    .EXAMPLE
    PS> Get-CurrentADSite
    This example shows how to call the Get-CurrentADSite function to retrieve the current Active Directory site name.

    .OUTPUTS
    String
    Returns the name of the Active Directory site or "Not Defined" if the site cannot be determined or an error occurs.
    #>
    
    Try {
        # Add the required assembly
        Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop
        
        # Create the directory context for the current domain
        $directoryContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain)
        
        # Get the domain using the directory context
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($directoryContext)
        
        # Get the current site of the computer
        $site = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite()
        
        # Check if the site is not null and return its name, otherwise return "Not Defined"
        If ($site -ne $null) {
            Return $site.Name
        } Else {
            Return "Not Defined"
        }
    } Catch {
        # If any errors occur, return "Not Defined"
        Return "Not Defined"
    }
}

Function Write-LockFile {
    <#
    .SYNOPSIS
    Creates or overwrites a .lock file with the name of the computer.

    .DESCRIPTION
    The Write-LockFile function takes a VHDX file path, changes its extension to .lock,
    and writes the name of the current computer into this lock file, overwriting any existing file.

    .PARAMETER vhdxPath
    The path of the VHDX file whose extension will be changed to .lock.

    .EXAMPLE
    Write-LockFile -vhdxPath '\\10-222-23-97\vhdx\dt234083-adm.vhdx'
    This example changes the extension of 'dt234083-adm.vhdx' to 'dt234083-adm.lock' and writes the computer's name to the .lock file.

    .NOTES
    Ensure that you have the necessary permissions to write to the specified path.

    #>
    
    Param (
        [string]$vhdxPath
    )
    
    # Change the extension to .lock
    $lockPath = $vhdxPath -replace '\.vhdx$', '.lock'
    
    # Get the name of the computer
    $computerName = $env:COMPUTERNAME
    
    # Write the computer name to the lock file, overwriting any existing file
    $computerName | Out-File -FilePath $lockPath -Force
}

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
	    Log-Message -message "Process completed successfully"
	    Logs the message with a timestamp to the console and to 'C:\temp\automationlog.log'.
	.EXAMPLE
	    Log-Message -message "User logged in" -filePath "C:\logs\userlog.log"
	    Logs the message to the console and to a specified file path.
	.NOTES
	    Author: Your Name
	    Date: Insert the current date
	    This function requires that the user has the necessary permissions to create directories and write to files in the specified paths.
	#>
    
    Param (
        [Parameter(Mandatory = $true)]
        [string]$message,
        [string]$filePath = "$env:USERPROFILE\VHDX_Mount.log"
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

Function Create-VHDX {
    <#
    .SYNOPSIS
    Creates and prepares a VHDX file with specified parameters.

    .DESCRIPTION
    The Create-VHDX function creates a dynamically expanding VHDX file at a specified path, initializes it, and formats it with an NTFS file system. It also assigns a designated drive letter to the new volume.

    .PARAMETER VHDPath
    Specifies the path where the VHDX file will be created.

    .PARAMETER SizeGB
    Specifies the size of the VHDX file in gigabytes. Default is 100 GB.

    .PARAMETER DriveLetter
    Specifies the drive letter to assign to the new volume. Default is 'L'.

    .EXAMPLE
    Create-VHDX -VHDPath "C:\VHDX\MyDisk.vhdx" -SizeGB 50 -DriveLetter 'M'
    Creates a 50 GB VHDX file at C:\VHDX\MyDisk.vhdx and assigns the drive letter M to the new volume.
    #>
    
    Param (
        [Parameter(Mandatory = $true)]
        [string]$VHDXPath,
        [Parameter(Mandatory = $false)]
        [int]$SizeGB = 200,
        [Parameter(Mandatory = $false)]
        [char]$DriveLetter = 'L'
    )
    
    Log-Message -message "Creating new VHDX file $($VHDXPath)"
    Log-Message -message "Size = $($SizeGB)GB"
    Log-Message -message "Drive Letter = $($DriveLetter)"
    
    Try {
        # Create a new VHDX file
        $userLDrive = New-VHD -Path $VHDXPath -SizeBytes ($SizeGB * 1GB) -Dynamic -ErrorAction Stop
        Mount-VHD -Path $VHDXPath
        Write-LockFile -vhdxPath $VHDXPath
        
        # Attempt to retrieve and initialize the disk
        $disk = Get-Disk | Where-Object { $_.BusType -eq 'File Backed Virtual' -and $_.PartitionStyle -eq 'Raw' }
        If ($disk) {
            Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop
            $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $DriveLetter -ErrorAction Stop
            
            # Format the partition
            Format-Volume -DriveLetter $DriveLetter -FileSystem NTFS -NewFileSystemLabel "VHDX_$($env:USERNAME)" -Confirm:$false
        } Else {
            Log-Message -message "No disk found at the specified path or the disk is not in Raw state."
        }
    } Catch {
        Log-Message -message  "An error occurred: $($_.Exception.Message)"
    }
}

Function Expand-VHDX {
    Param (
        [string]$VHDXPath,
        [int]$AdditionalSizeGB
    )
    
    If (!(Test-Path $VHDXPath)) {
        Log-Message -message "VHDX Does not exist, exiting."
        return 99
    }
    
    $vhdMounted = Get-Disk | Where-Object { $_.location -eq $VHDXPath }
        
    If (($vhdMounted | Measure-Object).count -eq 1) {
        Dismount-VHD -Path $VHDXPath
        Log-Message -message "VHDX dismounted for resizing."
    }
    
    $vhd = Get-VHD $VHDXPath
    $newSize = $vhd.Size + ($AdditionalSizeGB * 1GB)
    Resize-VHD -Path $VHDXPath -SizeBytes $newSize
    
    Mount-VHD -Path $VHDXPath
    Write-LockFile -vhdxPath $VHDXPath
    
    $vhdMounted = Get-Disk | Where-Object { $_.location -eq $VHDXPath }
    
    
    $diskNumber = $vhdMounted.DiskNumber
    $partition = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -NE "Reserved" }
    
    $size = (Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber)
    
    Resize-Partition -PartitionNumber $partition.PartitionNumber -Size $size.SizeMax -DiskNumber $partition.DiskNumber
    Log-Message -message "VHDX expanded by $AdditionalSizeGB GB.  New size is $([math]::round($size.SizeMax/1gb))GB"
}

Function Mount-VHDX {
    Param (
        [string]$VHDXPath
    )
    
    # Check if the VHDX file exists
    If (!(Test-Path $VHDXPath)) {
        Log-Message -message "VHDX file not found, creating new one..."
        Try {
            Create-VHDX -VHDXPath $VHDXPath
        } Catch {
            Log-Message -message "Failed to create VHDX: $_"
            return 99
        }
    }
    
    Try {
        If (Test-VHDXMounted -VHDXPath $VHDXPath) {
            Log-Message -message "VHDX already mounted, no action taken"
        } Else {
            Mount-VHD -Path $VHDXPath -ReadOnly:$false
            Write-LockFile -vhdxPath $VHDPath
            Log-Message -message "VHDX mounted successfully."
        }
    } Catch {
        Log-Message -message "Failed to mount VHDX: $_"
    }
    
    
}


Log-Message -message "Scrirpt initialized using PID $($PID)..."
Log-Message -message "Running as an administrator = $(Get-IsAdministrator)"

$ADSite = Get-CurrentADSite

Log-Message -message "AD Site returned = $($ADSite)"

#Pure Locations need to be added after testing is complete
switch ($ADSite) {
    'US-MO-WDC-Core' {
        $vhdxPath = "\\10-222-23-97\vhdx\$($env:USERNAME).vhdx"
	}
    'US-MO-STL-CORE' {
        #This needs to be define properly
        $vhdxPath = "\\<Some STL location>\vhdx\$($env:USERNAME).vhdx"
	}
	default {
        Log-Message -message "$($ADSite) has not been defined, exiting VHDX Mount Script"
        Exit 99
	}
}

$ServerShare = Split-Path $vhdxPath -Parent

If (!(Test-Path $ServerShare)) {
    Log-Message -message "Could not connect to $($ServerShare), Exiting VHDX Mount Script"
    Exit 99
}

# Check if the VHDX file exists
If (!(Test-Path $VHDXPath)) {
    Log-Message -message "VHDX file not found, creating new one..."
    Try {
        If (!(Get-IsAdministrator)) {
            If (Get-IsUacEnabled) {
                # We are not running "as Administrator" - so relaunch as administrator
                # Create a new process object that starts PowerShell
                $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
                
                # Specify the current script path and name as a parameter`
                $parameters = ""
                ForEach ($boundParam In $PSBoundParameters.GetEnumerator()) {
                    $parameters = "$parameters -{0} '{1}'" -f $boundParam.Key, $boundParam.Value
                }
                
                $newProcess.Arguments = $myInvocation.MyCommand.Definition, $parameters
                
                # Specify the current working directory
                $newProcess.WorkingDirectory = "$script_path"
                
                # Indicate that the process should be elevated
                $newProcess.Verb = "runas";
                
                # Start the new process
                [System.Diagnostics.Process]::Start($newProcess);
                
                # Exit from the current, unelevated, process
                Exit
            } Else {
                Log-Message -message "You must be administrator to run this script"
                Throw "You must be administrator to run this script"
            }
        }
        
        Create-VHDX -VHDXPath $VHDXPath
    } Catch {
        Log-Message -message "Failed to create VHDX: $_"
        Return 99
    }
}

Log-Message -message "Using folder location $($ServerShare).  Access test was successfull."

Mount-VHDX -VHDXPath $vhdxPath
