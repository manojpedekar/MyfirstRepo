Function Sync-VolumeLabels {
    <#
    .SYNOPSIS
        Syncs volume labels from a remote computer to the local computer for matching drive letters.
    
    .DESCRIPTION
        Reads volume labels from all fixed drives on a remote system and updates the labels
        on the local computer where the same drive letters exist.
    
    .PARAMETER ComputerName
        The name or IP address of the remote computer.
    
    .PARAMETER Credential
        Optional credentials to connect to the remote computer.
    
    .PARAMETER IgnoreSystemDisk
        If specified, excludes the system drive (typically C:) from both remote and local operations.
    
    .EXAMPLE
        Sync-VolumeLabels -ComputerName "SERVER01"
    
    .EXAMPLE
        $cred = Get-Credential
        Sync-VolumeLabels -ComputerName "SERVER01" -Credential $cred
    
    .EXAMPLE
        Sync-VolumeLabels -ComputerName "SERVER01" -IgnoreSystemDisk
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,
        [Parameter(Mandatory = $false)]
        [switch]$IgnoreSystemDisk
    )
    
    Try {
        # Build parameters for Invoke-Command
        $invokeParams = @{
            ComputerName = $ComputerName
            ErrorAction  = 'Stop'
        }
        
        If ($Credential) {
            $invokeParams['Credential'] = $Credential
        }
        
        # Get fixed drives from remote computer
        Write-Verbose "Retrieving fixed drive information from $ComputerName..."
        $remoteDrives = Invoke-Command @invokeParams -ScriptBlock {
            Param ($IgnoreSys)
            
            $drives = Get-Volume | Where-Object {
                $_.DriveType -eq 'Fixed' -and
                $_.DriveLetter -ne $null
            }
            
            # Filter out system disk if requested
            If ($IgnoreSys) {
                $systemDrive = $env:SystemDrive.TrimEnd(':')
                $drives = $drives | Where-Object { $_.DriveLetter -ne $systemDrive }
            }
            
            $drives | Select-Object DriveLetter, FileSystemLabel
        } -ArgumentList $IgnoreSystemDisk
        
        If (-not $remoteDrives) {
            Write-Warning "No fixed drives found on remote computer $ComputerName"
            Return
        }
        
        Write-Host "`nFound $($remoteDrives.Count) fixed drive(s) on $ComputerName" -ForegroundColor Cyan
        
        # Get local fixed drives
        $localDrives = Get-Volume | Where-Object {
            $_.DriveType -eq 'Fixed' -and
            $_.DriveLetter -ne $null
        }
        
        # Filter out system disk if requested
        If ($IgnoreSystemDisk) {
            $systemDrive = $env:SystemDrive.TrimEnd(':')
            $localDrives = $localDrives | Where-Object { $_.DriveLetter -ne $systemDrive }
            Write-Verbose "Ignoring system drive ($systemDrive) on both local and remote systems"
        }
        
        # Process each remote drive
        ForEach ($remoteDrive In $remoteDrives) {
            $driveLetter = $remoteDrive.DriveLetter
            $remoteLabel = $remoteDrive.FileSystemLabel
            
            # Find matching local drive
            $localDrive = $localDrives | Where-Object { $_.DriveLetter -eq $driveLetter }
            
            If ($localDrive) {
                $currentLabel = $localDrive.FileSystemLabel
                
                If ($currentLabel -ne $remoteLabel) {
                    $message = "Drive ${driveLetter}: - Updating label from '$currentLabel' to '$remoteLabel'"
                    
                    If ($PSCmdlet.ShouldProcess("Drive ${driveLetter}:", "Update volume label to '$remoteLabel'")) {
                        Try {
                            Set-Volume -DriveLetter $driveLetter -NewFileSystemLabel $remoteLabel -ErrorAction Stop
                            Write-Host "✓ $message" -ForegroundColor Green
                        } Catch {
                            Write-Error "Failed to update label for drive ${driveLetter}: $($_.Exception.Message)"
                        }
                    }
                } Else {
                    Write-Host "○ Drive ${driveLetter}: - Label already matches ('$currentLabel')" -ForegroundColor Gray
                }
            } Else {
                Write-Host "⊘ Drive ${driveLetter}: - Not found on local computer (Remote label: '$remoteLabel')" -ForegroundColor Yellow
            }
        }
    } Catch {
        Write-Error "Error connecting to $ComputerName : $($_.Exception.Message)"
    }
}

