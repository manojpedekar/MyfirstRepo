# Merged Server Management Script

# Function to display menu and get user choice
function Show-Menu {
    Clear-Host
    Write-Host "===== Server Management Menu ====="
    Write-Host "1 - Run Inventory Permissions Script"
    Write-Host "2 - Build Folders and Apply Groups on New Server-Shares"
    Write-Host "3 - Build Shares on new Server"
    Write-Host "Q - Quit"
    Write-Host "===================================="
    $choice = Read-Host "Enter your choice"
    return $choice
}

# Function to get initial data
function Get-InitialData {
    $script:JIRA_Ticket_Number = Read-Host "Enter JIRA Ticket Number"
    $script:Source_Server_Name = Read-Host "Enter Source Server Name"
    $script:Destination_Server_Name = Read-Host "Enter Destination Server Name"

    # Save data to a single text file
    $migrationData = @"
JIRA Ticket Number: $JIRA_Ticket_Number
Source Server Name: $Source_Server_Name
Destination Server Name: $Destination_Server_Name
"@
    $migrationData | Out-File "$JIRA_Ticket_Number-File-Migration-Data.txt"
}

# Function to get drive information
function Get-DriveInfo {
    $drives = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType = 3"
    $driveInfoList = @()
    foreach ($drive in $drives) {
        $driveInfo = [PSCustomObject]@{
            'ServerName'    = $env:COMPUTERNAME
            'DriveLetter'   = $drive.DeviceID
            'TotalCapacity' = "{0:N2} GB" -f ($drive.Size / 1GB)
            'UsedCapacity'  = "{0:N2} GB" -f (($drive.Size - $drive.FreeSpace) / 1GB)
        }
        $driveInfoList += $driveInfo
    }
    return $driveInfoList
}

# Function to run Inventory Permissions Script
function Run-InventoryScript {
    # Mail Configuration
    $smtpServer = "mailrelay.ssnc-corp.cloud"
    $emailFrom = "globalwindowsservers@sscinc.com"
    $emailTo = Read-Host "Enter your email address"
    $portNumber = 25

    # Get the hostname of the server
    $hostname = $env:COMPUTERNAME

    # Construct the directory name
    $subdirectoryName = "$JIRA_Ticket_Number-$Source_Server_Name-export"

    # Set $ExportPath
    $ExportPath = Join-Path -Path $pwd -ChildPath $subdirectoryName

    # Create the subdirectory
    New-Item -ItemType Directory -Path $ExportPath -Force

    # Define filenames
    $filename = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-PermissionExport-All-Shares.csv"
    $filename2 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-installed-software.csv"
    $filename3 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-installed-features.csv"
    $filename4 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-running-services.csv"
    $filename5 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-running-processes.csv"
    $filename6 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-system-information.txt"
    $filename7 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-drive-information.csv"
    $filename8 = Join-Path $ExportPath "$JIRA_Ticket_Number-$Source_Server_Name-Server-Shares.csv"

    # Zip Configuration
    $zipFileName = "ExportedData_$JIRA_Ticket_Number-$Source_Server_Name.zip"
    $zipFilePath = Join-Path $ExportPath $zipFileName

    # Get PowerShell version
    $psVersion = $PSVersionTable.PSVersion

    # Use the proper command for share retrieval
    $sharename = if (Get-Command Get-SmbShare -ErrorAction SilentlyContinue) {
        Get-SmbShare | Select-Object Name, Path
    } else {
        Get-WmiObject -Class Win32_Share | Where-Object { $_.Type -eq 0 } | Select-Object Name, Path
    }

    # Export server shares to CSV
    $sharename | Export-Csv -Path $filename8 -NoTypeInformation

    # Results variable for all data
    $results = @()

    # Loop through Shares on the server
    foreach ($Share in $shareName) {
        # Setting script parameters for each share
        $FolderPath = $Share.Path
        $shareName = $Share.Name
        $shareSize = Get-ChildItem -Path $Share.Path | Measure-Object -Property Length -Sum

        # Results variable for each share
        $resultsPerShare = @()

        # Get Folders
        $error.clear()
        $Folders = Get-ChildItem -Path $FolderPath -Directory | Select-Object Name, FullName, LastWriteTime, Length
        foreach ($err in $Error) {
            $err.Exception.Message | Out-File "$ExportPath\AccessDenied.txt" -Append
        }

        # Loop through folders
        foreach ($Folder in $Folders) {
            # Get Size of each folder
            $size = ((Get-ChildItem -Path $Folder.FullName -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB)

            # Get access control list
            $Acls = Get-Acl -Path $Folder.FullName -ErrorAction SilentlyContinue

            # Loop through ACL
            foreach ($Acl in $Acls.Access) {
                if (!$Acl.IsInherited -and
                    $Acl.IdentityReference -notlike "BUILTIN\Administrators" -and
                    $Acl.IdentityReference -notlike "CREATOR OWNER" -and
                    $Acl.IdentityReference -notlike "NT AUTHORITY\SYSTEM" -and
                    $Acl.FileSystemRights -notlike "-*" -and
                    $Acl.FileSystemRights -notlike "268435456" -and
                    $Acl.IdentityReference -notlike "S-1-*") {

                    # Format properties for result hash table
                    $properties = @{
                        ServerName        = $hostname
                        ShareName         = $Share.Name
                        Share_Size        = $shareSize
                        FolderName        = $Folder.Name
                        FolderPath        = $Folder.FullName
                        LastWriteTime     = $Folder.LastWriteTime
                        IdentityReference = $Acl.IdentityReference.ToString()
                        Folder_Size       = [math]::Round($size, 2)
                        Permissions       = $Acl.FileSystemRights
                        AccessControlType = $Acl.AccessControlType.ToString()
                        IsInherited       = $Acl.IsInherited
                    }

                    $resultsPerShare += New-Object PSObject -Property $properties
                }
            }
        }

        # Add results for each share to the main results array
        $results += $resultsPerShare
    }

    # Export all results to a single CSV file
    $results | Export-Csv -Path $filename -NoTypeInformation

    # Get additional information from the server
    # Installed Software
    $installedSoftware = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion
    $installedSoftware | Export-Csv -Path $filename2 -NoTypeInformation

    # Installed Features
    $installedFeatures = dism /online /get-features /format:table | Where-Object { $_ -match "Enabled" } | ForEach-Object { $_ -replace '\s+Enabled', '' } | ConvertFrom-String | Select-Object -Property "Feature Name", "Feature Enabled" | Export-Csv -Path $filename3 -NoTypeInformation

    # Installed Services
    $runningServices = Get-Service | Where-Object { $_.Status -eq "Running" } | Select-Object DisplayName, Status | Export-Csv -Path $filename4 -NoTypeInformation

    # Running Processes
    $runningProcesses = Get-Process | Select-Object Name, Id | Export-Csv -Path $filename5 -NoTypeInformation

    # Collect system information to TXT file
    $systemInfoObject = systeminfo > $filename6

    # Collect drive information
    $driveInfoList = Get-DriveInfo

    # Export drive information to CSV
    $driveInfoList | Export-Csv -Path $filename7 -NoTypeInformation

    # Zip up all exported files
    Compress-Archive -Path "$ExportPath\*" -DestinationPath $zipFilePath -Force

    # Test the connection to mailrelay.ssnc-corp.cloud on port 25
    $mailRelayTest = Test-NetConnection -ComputerName $smtpServer -Port $portNumber

    if ($mailRelayTest.TcpTestSucceeded) {
        # If the test connection is successful, send the zip file via email
        $smtp = New-Object Net.Mail.SmtpClient($smtpServer)
        $message = New-Object Net.Mail.MailMessage($emailFrom, $emailTo, "Exported Data - $hostname - JIRA Ticket: $JIRA_Ticket_Number", "Please find attached the exported data from $hostname for JIRA Ticket: $JIRA_Ticket_Number.")
        $attachment = New-Object Net.Mail.Attachment($zipFilePath)
        $message.Attachments.Add($attachment)
        $smtp.Send($message)
        Write-Host "Email sent successfully."
    } else {
        Write-Host "Failed to test connection to $smtpServer on port $portNumber."
    }
}

# Function to build folders and apply groups
function Build-FoldersApplyGroups {
    # Get the server's DNS name
    $serverDNSName = [System.Net.Dns]::GetHostEntry([string]$env:computername).HostName

    # Input and output file paths
    $inputFile = "$JIRA_Ticket_Number-$Destination_Server_Name-Build-Folders-Apply-Groups.csv"
    $outputFile = ".\$serverDNSName-Output-Applied_Permissions_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $logFile = ".\$serverDNSName-FolderSetup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # Function to write to both console and log file
    function Write-Log {
        param (
            [string]$Message
        )
        Write-Output $Message
        Add-Content -Path $logFile -Value $Message
    }

    # Start logging
    Write-Log "Script execution started at $(Get-Date)"
    Write-Log "Server DNS Name: $serverDNSName"
    Write-Log "Input file: $inputFile"
    Write-Log "Output file: $outputFile"
    Write-Log "Log file: $logFile"

    # Import data from CSV
    Write-Log "Importing data from $inputFile"
    $data = Import-Csv $inputFile

    # Initialize an array to store results
    $results = @()

    # Get total number of entries for progress reporting
    $totalEntries = $data.Count
    $currentEntry = 0

    # Loop through each entry in the CSV
    foreach ($entry in $data) {
        $currentEntry++
        $percentComplete = [math]::Round(($currentEntry / $totalEntries) * 100, 2)
        
        # Update progress bar
        Write-Progress -Activity "Processing Folders and Permissions" -Status "Progress: $percentComplete% Complete" -PercentComplete $percentComplete

        Write-Log "`nProcessing entry $currentEntry of $totalEntries ($percentComplete%)"
        
        $IdentityReference = $entry.IdentityReference
        $FolderPath = $entry.FolderPath
        $Permissions = $entry.Permissions
        
        Write-Log "  Working on folder: $FolderPath"
        
        # Check if the folder exists, if not, create it
        if (-not (Test-Path $FolderPath)) {
            try {
                New-Item -Path $FolderPath -ItemType Directory -Force
                Write-Log "  Folder created: $FolderPath"
            } catch {
                Write-Log "  Failed to create folder: $FolderPath"
                Write-Log "  Error: $($_.Exception.Message)"
                $Permissions_Applied = "Folder Creation Failed"
                continue
            }
        }
        
        # Set permissions for the folder
        try {
            $acl = Get-Acl $FolderPath
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$IdentityReference", 
                "$Permissions", 
                "ContainerInherit,ObjectInherit", 
                "None", 
                "Allow"
            )
            $acl.SetAccessRule($rule)
            Set-Acl $FolderPath $acl
            Write-Log "  Permissions applied for $IdentityReference on $FolderPath"
            $Permissions_Applied = "Successful"
        } catch {
            Write-Log "  Failed to apply permissions for $IdentityReference on $FolderPath"
            Write-Log "  Error: $($_.Exception.Message)"
            $Permissions_Applied = "Failed"
        }
        
        # Add result to results array
        $results += [PSCustomObject]@{
            Server_Name = $serverDNSName
            IdentityReference = $IdentityReference
            FolderPath = $FolderPath
            Permissions = $Permissions
            Permissions_Applied = $Permissions_Applied
        }
    }

    # Complete the progress bar
    Write-Progress -Activity "Processing Folders and Permissions" -Completed

    # Export results to CSV
    Write-Log "`nExporting results to $outputFile"
    $results | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Log "Results exported to CSV file"

    # Log script completion
    Write-Log "Script execution completed at $(Get-Date)"
}

# Function to build shares on new server
function Build-NewServerShares {
    $inputFile = "$JIRA_Ticket_Number-$Source_Server_Name-Server-Shares.csv"
    $shares = Import-Csv $inputFile

    foreach ($share in $shares) {
        $shareName = $share.Name
        $sharePath = $share.Path

        # Create the directory if it doesn't exist
        if (-not (Test-Path $sharePath)) {
            New-Item -Path $sharePath -ItemType Directory -Force
        }

        # Create the share
        New-SmbShare -Name $shareName -Path $sharePath -FullAccess "Everyone"
        Write-Host "Created share: $shareName on path: $sharePath"
    }
}

# Main script
Get-InitialData

do {
    $choice = Show-Menu
    switch ($choice) {
        '1' {
            Run-InventoryScript
            Write-Host "Inventory Permissions Script completed."
            pause
        }
        '2' {
            Build-FoldersApplyGroups
            Write-Host "Build Folders and Apply Groups completed."
            pause
        }
        '3' {
            Build-NewServerShares
            Write-Host "Build Shares on new Server completed."
            pause
        }
        'Q' {
            Write-Host "Exiting script. Goodbye!"
            break
        }
        default {
            Write-Host "Invalid choice. Please try again."
            pause
        }
    }
} while ($choice -ne 'Q')

# End of script
