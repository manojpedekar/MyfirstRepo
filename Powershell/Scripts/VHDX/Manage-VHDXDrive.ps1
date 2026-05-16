<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	3/21/2025 3:33 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Manage-VHDXDrive.ps1
	===========================================================================
	.DESCRIPTION
		This script is designed to mount or expand a VHDX file for developers
#>

Param (
    [switch]$Mount,
    [switch]$Expand,
    [int]$AdditionalSizeGB,
    [string]$DriveLetter = "E:\"
)

###########################################
##              FUNCTIONS                ##
###########################################

Function Test-SecurityGroupMembership {
    Param (
        [string]$groupName
    )
    
    $currentUser = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    $group = New-Object System.Security.Principal.NTAccount($groupName)
    
    Try {
        Return $currentUser.IsInRole($group)
    } Catch {
        Log-Message -message "Failed to check group membership. The group may not exist or the name is incorrect."
        Return $false
    }
}

Function Show-Form {
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PowerShell Form"
    $form.Size = New-Object System.Drawing.Size(300, 200)
    $form.StartPosition = "CenterScreen"
    
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(75, 120)
    $okButton.Size = New-Object System.Drawing.Size(150, 23)
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)
    
    $form.Topmost = $true
    $form.Add_Shown({ $form.Activate() })
    $result = $form.ShowDialog()
    
    If ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Form closed with OK"
    }
}

Function Get-IsUacEnabled {
    (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System).EnableLua -ne 0
}

Function Get-IsAdministrator {
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
    $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
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

Function Test-VHDXMounted {
    Param (
        [string]$VHDXPath
    )
    
    $vhdMounted = Get-Disk | Where-Object { $_.location -eq $VHDXPath }
    
    If ($vhdMounted) {
        Return $true
    }
    
    Return $false
    
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
        [string]$VHDXPath
    )
    
    # Change the extension to .lock
    $lockPath = $VHDXPath -replace '\.vhdx$', '.lock'
    
    # Get the name of the computer
    $computerName = $env:COMPUTERNAME
    
    # Write the computer name to the lock file, overwriting any existing file
    $computerName | Out-File -FilePath $lockPath -Force
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
            Log-Message -message "Drive created sucessfully! "
        } Else {
            Log-Message -message "No disk found at the specified path or the disk is not in Raw state."
        }
    } Catch {
        Log-Message -message "An error occurred: $($_.Exception.Message)"
    }
}

Function Mount-VHDX {
    Param (
        [string]$VHDXPath
    )
    
    Try {
        If (Test-VHDXMounted -VHDXPath $VHDXPath) {
            Log-Message -message "VHDX already mounted, no action taken"
        } Else {
            Mount-VHD -Path $VHDXPath -ReadOnly:$false
            Write-LockFile $VHDXPath $VHDPath
            Log-Message -message "VHDX mounted successfully."
        }
    } Catch {
        Log-Message -message "Failed to mount VHDX: $_"
    }
    
    
}

Function Get-VHDXSize {
    Param (
        [string]$VHDXPath
    )
    
    Try {
        $vhdMounted = Get-Disk | Where-Object { $_.location -eq $VHDXPath }
        
        $diskNumber = $vhdMounted.DiskNumber
        $partition = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -NE "Reserved" }
        
        Return (Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber)
        
    } Catch {
        Log-Message -message "Failed to get VHDX size: $_"
    }
    
    
}

Function Expand-VHDX {
    Param (
        [string]$VHDXPath,
        [int]$AdditionalSizeGB
    )
    
    If (!(Test-Path $VHDXPath)) {
        Log-Message -message "VHDX Does not exist, exiting."
        Return 99
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

###########################################
##                 VARS                  ##
###########################################
[version]$version = '1.1.0'

$HyperVAdmin = "Hyper-V Administrators"
$HVMember = Test-SecurityGroupMembership -groupName $HyperVAdmin
$IsAdmin = Get-IsAdministrator

$ADSite = Get-CurrentADSite

Switch ($ADSite) {
    'US-MO-WDC-Core' {
        #$VHDXPath = "\\10-222-23-97\vhdx\$($env:USERNAME).vhdx"
        $vhdxPath= "\\wdc-pure-13-file-vif01.sscclient161.ssncad.global\LDrive\$($env:USERNAME).vhdx"
    }
    'US-MO-STL-CORE' {
        $VHDXPath = "\\bdc-pure-13-file-vif01.sscclient161.ssncad.global\LDrive\$($env:USERNAME).vhdx"
    }
    default {
        Log-Message -message "$($ADSite) has not been defined, exiting VHDX Mount Script"
        Exit 99
    }
}


#New-VirtualDisk -StoragePoolFriendlyName CompanyData -FriendlyName UserData -Size 100GB

$ServerShare = Split-Path $VHDXPath -Parent
$VHDXExists = Test-Path $VHDXPath
$LDriveMounted = Test-VHDXMounted -VHDXPath $VHDXPath

# Log Initial Parameters using a loop
$paramLog = "Script started with parameters: "
ForEach ($param In $PSBoundParameters.GetEnumerator()) {
    $paramLog += "$($param.Key): '$($param.Value)', "
}

# Trim the trailing comma and space
$paramLog = $paramLog.TrimEnd(", ")


###########################################
##               SCRIPT                  ##
###########################################

Log-Message -message "***********************************************************"
Log-Message -message "Scrirpt initialized using PID $($PID)"
Log-Message -message "Running as an administrator = $($IsAdmin)"
Log-Message -message "AD Site returned = $($ADSite)"
Log-Message -message "User VHDX = $($VHDXPath)"
Log-Message -message $paramLog

If ($HVMember) {
    Log-Message -message "User is a member of required group $($HyperVAdmin)"
} Else {
    Log-Message -message "User is not a member of required group $($HyperVAdmin), Exiting!"
    exit 99
}

If ($mount -and $expand) {
    Log-Message -message "You cannot specify both -mount and -expand at the same time, Exiting VHDX Mount Script."
    Write-Error "You cannot specify both -Mount and -Expand at the same time, Exiting VHDX Mount Script."
    exit 99
}

If (!(Test-Path $ServerShare)) {
    Log-Message -message "Could not connect to $($ServerShare), Exiting VHDX Mount Script"
    Exit 99
}

If ($mount) {
    
    If (Test-Path -Path $DriveLetter) {
        Log-Message -message "Mount option was used when drive already present. LDriveMounted = $($LDriveMounted)"
        exit 99
    }
        
    If (!(Test-Path $VHDXPath)) {
        Log-Message -message "VHDX file not found, creating new one..."
        Try {
            If (!(Get-IsAdministrator)) {
                If (Get-IsUacEnabled) {
                    Log-Message -message "We are not running as Administrator - so relaunch as administrator"
                    # Create a new process object that starts PowerShell
                    
                    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
                    
                    # Specify the current script path and name as a parameter
                    $parameters = ""
              
                    ForEach ($boundParam In $PSBoundParameters.GetEnumerator()) {
                        # Get parameter metadata
                        $paramMetadata = $MyInvocation.MyCommand.Parameters[$boundParam.Key]
                        
                        If ($paramMetadata.ParameterType.Name -eq 'SwitchParameter') {
                            # For switches, add just the key if switch is set
                            If ($boundParam.Value) {
                                $parameters = "$parameters -{0}" -f $boundParam.Key
                            }
                        } ElseIf ($paramMetadata.ParameterType.Name -in 'Int16', 'Int32', 'Int64') {
                            # For integer types, handle differently if necessary
                            $parameters = "$parameters -{0} {1}" -f $boundParam.Key, $boundParam.Value
                        } Else {
                            # For other types, add key and value
                            $parameters = "$parameters -{0} '{1}'" -f $boundParam.Key, $boundParam.Value
                            Write-Host $paramMetadata.ParameterType.Name
                        }
                    }
                    
                    
                    $newProcess.Arguments = $myInvocation.MyCommand.Definition, $parameters
                    
                    # Specify the current working directory
                    $newProcess.WorkingDirectory = "$script_path"
                    
                    # Indicate that the process should be elevated
                    $newProcess.Verb = "runas";
                    
                    Log-Message -message "Restarting script in Admin context using"
                    Log-Message -message "    $($myInvocation.MyCommand.Definition) $($parameters)"
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
    } Else {
        Log-Message -message "Using folder location $($ServerShare).  Access test was successfull."
        Mount-VHDX -VHDXPath $vhdxPath
    }
    
} ElseIf ($expand) {
    # Expand-VHDX -VHDXPath $VHDXPath -AdditionalSizeGB $AdditionalSizeGB
    
    If (Test-Path $VHDXPath) {
        Log-Message -message "VHDX file found, Testing admin privs prior to expand..."
        Try {
            If (!(Get-IsAdministrator)) {
                If (Get-IsUacEnabled) {
                    Log-Message -message "We are not running as Administrator - so relaunch as administrator"
                    # Create a new process object that starts PowerShell
                    
                    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
                    
                    # Specify the current script path and name as a parameter
                    $parameters = ""
                    
                    ForEach ($boundParam In $PSBoundParameters.GetEnumerator()) {
                        # Get parameter metadata
                        $paramMetadata = $MyInvocation.MyCommand.Parameters[$boundParam.Key]
                        
                        If ($paramMetadata.ParameterType.Name -eq 'SwitchParameter') {
                            # For switches, add just the key if switch is set
                            If ($boundParam.Value) {
                                $parameters = "$parameters -{0}" -f $boundParam.Key
                            }
                        } ElseIf ($paramMetadata.ParameterType.Name -in 'Int16', 'Int32', 'Int64') {
                            # For integer types, handle differently if necessary
                            $parameters = "$parameters -{0} {1}" -f $boundParam.Key, $boundParam.Value
                        } Else {
                            # For other types, add key and value
                            $parameters = "$parameters -{0} '{1}'" -f $boundParam.Key, $boundParam.Value
                            Write-Host $paramMetadata.ParameterType.Name
                        }
                    }
                    
                    $newProcess.Arguments = $myInvocation.MyCommand.Definition, $parameters
                    
                    # Specify the current working directory
                    $newProcess.WorkingDirectory = "$script_path"
                    
                    # Indicate that the process should be elevated
                    $newProcess.Verb = "runas";
                    
                    Log-Message -message "Restarting script in Admin context using"
                    Log-Message -message "    $($myInvocation.MyCommand.Definition) $($parameters)"
                    # Start the new process
                    [System.Diagnostics.Process]::Start($newProcess);
                    
                    # Exit from the current, unelevated, process
                    Exit
                } Else {
                    Log-Message -message "You must be administrator to run this script"
                    Throw "You must be administrator to run this script"
                }
            }
            Expand-VHDX -VHDXPath $VHDXPath -AdditionalSizeGB $AdditionalSizeGB
        } Catch {
            Log-Message -message "Failed to expand VHDX: $_"
            Return 99
        }
    } Else {
        Log-Message -message "Using folder location $($ServerShare).  Access test was not successfull. VHDX not expanded."
        Exit 99
    }
    
    
} Else {
    
    Log-Message -message "In the else statement"
    
    If (!(Get-IsAdministrator)) {
        If (Get-IsUacEnabled) {
            # We are not running "as Administrator" - so relaunch as administrator
            # Create a new process object that starts PowerShell
            $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
            
            # Specify the current script path and name as a parameter
            $parameters = ""
            
            ForEach ($boundParam In $PSBoundParameters.GetEnumerator()) {
                # Get parameter metadata
                $paramMetadata = $MyInvocation.MyCommand.Parameters[$boundParam.Key]
                
                If ($paramMetadata.ParameterType.Name -eq 'SwitchParameter') {
                    # For switches, add just the key if switch is set
                    If ($boundParam.Value) {
                        $parameters = "$parameters -{0}" -f $boundParam.Key
                    }
                } ElseIf ($paramMetadata.ParameterType.Name -in 'Int16', 'Int32', 'Int64') {
                    # For integer types, handle differently if necessary
                    $parameters = "$parameters -{0} {1}" -f $boundParam.Key, $boundParam.Value
                } Else {
                    # For other types, add key and value
                    $parameters = "$parameters -{0} '{1}'" -f $boundParam.Key, $boundParam.Value
                    Write-Host $paramMetadata.ParameterType.Name
                }
            }
            
            $newProcess.Arguments = $MyInvocation.MyCommand.Definition, $parameters
            
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
    
    Show-Form
}
