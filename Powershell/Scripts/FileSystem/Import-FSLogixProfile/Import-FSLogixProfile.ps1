
[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $true)]
    [string]$user,
    [string]$LogPath = "C:\temp\migration.log"
)

##################################
##          FUNCTIONS           ##
##################################

Function Get-LocalComputerADSite {
    [CmdletBinding()]
    Param ()
    
    Try {
        Add-Type -AssemblyName System.DirectoryServices
        
        $site = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite()
        Return $site.Name
    } Catch {
        Write-Error "Unable to determine AD site: $_"
        Return $null
    }
}

Function Get-FSXStoragePath {
    $ADSite = Get-LocalComputerADSite
    
    Switch ($ADSite) {
        'JA-TO-Core' {
            return '\\amznfsxbkwkvbds.sscclient161.ssncad.global\CTXFSLProfiles'
        }
        'RS-Sing-Core' {
            return '\\amznfsxoplvcmh2.sscclient161.ssncad.global\CTXFSLProfiles'
        }
        'UK-Marshfield-NG-Core' {
            return '\\ngd-pure-04-file-vif01.sscclient161.ssncad.global\CTXFSLProfiles'
        }
        'UK-Harlow-KAO-Core' {
            return '\\kao-pure-04-file-vif01.sscclient161.ssncad.global\CTXFSLProfiles'
        }
        'US-MO-WDC-Core' {
            return '\\wdc-pure-13-file-vif01.sscclient161.ssncad.global\CTXFSLProfiles'
        }
        'US-MO-STL-Core' {
            return '\\bdc-pure-13-file-vif01.sscclient161.ssncad.global\CTXFSLProfiles'
        }
        default {
            Throw "Unrecognized AD Site: $ADSite"
        }
    }
    
}

Function Get-ADDomainNetBIOSName {
    
    $root = [ADSI]"LDAP://RootDSE"
    $config = $root.configurationNamingContext
    $domain = $root.defaultNamingContext
    
    $ds = New-Object DirectoryServices.DirectorySearcher
    $ds.SearchRoot = [ADSI]"LDAP://CN=Partitions,$config"
    $ds.Filter = "(&(objectCategory=crossRef)(nCName=$domain))"
    
    return ($ds.FindOne().Properties['nETBIOSName'])[0]
       
}

Function Set-UserProfileRegistryEntryFromUser {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param (
        [Parameter(Mandatory)]
        [string]$UserName,
        [Parameter(Mandatory)]
        [string]$ProfileTargetPath,
        [string]$LogPath = "C:\temp\migration.log",
        # If present, save pre-existing values and try to restore them on failure
        [switch]$BackupExisting
    )
    
    # Force terminating errors so try/catch works reliably
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    Try {
        Log-Message -message "Starting registry update for user '$UserName' → ProfileImagePath='$ProfileTargetPath'." -filePath $LogPath
        
        If ([string]::IsNullOrWhiteSpace($UserName)) { Throw "UserName is empty." }
        If ([string]::IsNullOrWhiteSpace($ProfileTargetPath)) { Throw "ProfileTargetPath is empty." }
        
        # --- Lookup user in AD ---
        Log-Message -message "Querying AD for '$UserName' (objectSID, objectGUID)..." -filePath $LogPath
        $userSearcher = New-Object DirectoryServices.DirectorySearcher
        $userSearcher.Filter = "(&(objectClass=user)(sAMAccountName=$UserName))"
        $null = $userSearcher.PropertiesToLoad.AddRange(@("objectSID", "objectGUID"))
        $result = $userSearcher.FindOne()
        
        If (-not $result) {
            Throw "User '$UserName' not found in Active Directory."
        }
        
        $props = $result.Properties
        $sidBinary = $props.objectsid[0]
        $guid = [guid]::New($props.objectguid[0]).ToString()
        $sid = (New-Object System.Security.Principal.SecurityIdentifier($sidBinary, 0)).Value
        
        Log-Message -message "AD lookup OK: SID='$sid', GUID='{$guid}'." -filePath $LogPath
        
        # --- Registry path for ProfileList entry ---
        $baseKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
        
        # Ensure the key exists
        If (-not (Test-Path $baseKey)) {
            If ($PSCmdlet.ShouldProcess($baseKey, "Create profile registry key")) {
                Log-Message -message "Creating registry key: $baseKey" -filePath $LogPath
                New-Item -Path $baseKey -Force -ErrorAction Stop | Out-Null
            }
        } Else {
            Log-Message -message "Registry key already exists: $baseKey" -filePath $LogPath
        }
        
        # Optionally back up current values for rollback
        $preValues = $null
        If ($BackupExisting -and (Test-Path $baseKey)) {
            Try {
                $gip = Get-ItemProperty -Path $baseKey -ErrorAction Stop
                $preValues = @{
                    ProfileImagePath                        = $gip.ProfileImagePath
                    Guid                                    = $gip.Guid
                    Flags                                   = $gip.Flags
                    FullProfile                             = $gip.FullProfile
                    Sid                                     = $gip.Sid
                    State                                   = $gip.State
                    LocalProfileLoadTimeLow                 = $gip.LocalProfileLoadTimeLow
                    LocalProfileLoadTimeHigh                = $gip.LocalProfileLoadTimeHigh
                    ProfileAttemptedProfileDownloadTimeLow  = $gip.ProfileAttemptedProfileDownloadTimeLow
                    ProfileAttemptedProfileDownloadTimeHigh = $gip.ProfileAttemptedProfileDownloadTimeHigh
                    ProfileLoadTimeLow                      = $gip.ProfileLoadTimeLow
                    ProfileLoadTimeHigh                     = $gip.ProfileLoadTimeHigh
                    RunLogonScriptSync                      = $gip.RunLogonScriptSync
                    LocalProfileUnloadTimeLow               = $gip.LocalProfileUnloadTimeLow
                    LocalProfileUnloadTimeHigh              = $gip.LocalProfileUnloadTimeHigh
                }
                Log-Message -message "Backed up existing values for rollback." -filePath $LogPath
            } Catch {
                Log-Message -message "WARNING: Failed to back up existing values: $($_.Exception.Message)" -filePath $LogPath
            }
        }
        
        # Values to write (kept in one hashtable so logging + iteration is easy)
        $values = [ordered]@{
            ProfileImagePath = @{ Value = $ProfileTargetPath; Type = 'String' }
            Guid             = @{ Value = "{$guid}"; Type = 'String' }
            Flags            = @{ Value = 0; Type = 'DWord' }
            FullProfile      = @{ Value = 1; Type = 'DWord' }
            Sid              = @{ Value = $sidBinary; Type = 'Binary' }
            State            = @{ Value = 0; Type = 'DWord' }
            LocalProfileLoadTimeLow = @{ Value = 0x409f513d; Type = 'DWord' }
            LocalProfileLoadTimeHigh = @{ Value = 0x01d7e5b8; Type = 'DWord' }
            ProfileAttemptedProfileDownloadTimeLow = @{ Value = 0; Type = 'DWord' }
            ProfileAttemptedProfileDownloadTimeHigh = @{ Value = 0; Type = 'DWord' }
            ProfileLoadTimeLow = @{ Value = 0; Type = 'DWord' }
            ProfileLoadTimeHigh = @{ Value = 0; Type = 'DWord' }
            RunLogonScriptSync = @{ Value = 0; Type = 'DWord' }
            LocalProfileUnloadTimeLow = @{ Value = 0x2c3ee568; Type = 'DWord' }
            LocalProfileUnloadTimeHigh = @{ Value = 0x01d7e5c2; Type = 'DWord' }
        }
        
        ForEach ($name In $values.Keys) {
            $v = $values[$name]
            If ($PSCmdlet.ShouldProcess("$baseKey\$name", "Set $($v.Type) value")) {
                Log-Message -message "Setting '$name' = '$($v.Value)' (Type=$($v.Type))." -filePath $LogPath
                Set-ItemProperty -Path $baseKey -Name $name -Value $v.Value -Type $v.Type -ErrorAction Stop
            }
        }
        
        Log-Message -message "SUCCESS: Registry entry for '$UserName' written to $baseKey." -filePath $LogPath
        [pscustomobject]@{
            Success  = $true
            UserName = $UserName
            SID      = $sid
            GUID     = $guid
            Registry = $baseKey
        }
    } Catch {
        $err = $_ | Out-String
        Log-Message -message "ERROR updating registry for '$UserName': $err" -filePath $LogPath
        
        # Attempt rollback if requested and we have something to restore
        If ($BackupExisting -and $preValues) {
            Try {
                Log-Message -message "Attempting rollback of registry values at $baseKey..." -filePath $LogPath
                ForEach ($k In $preValues.Keys) {
                    # Only restore if the original existed (is not $null)
                    If ($null -ne $preValues[$k]) {
                        $type =
                        If ($k -eq 'Sid') { 'Binary' } ElseIf ($preValues[$k] -is [int]) { 'DWord' } Else { 'String' }
                        Set-ItemProperty -Path $baseKey -Name $k -Value $preValues[$k] -Type $type -ErrorAction Stop
                    } Else {
                        # Remove the value if it didn't exist originally
                        If (Get-ItemProperty -Path $baseKey -Name $k -ErrorAction SilentlyContinue) {
                            Remove-ItemProperty -Path $baseKey -Name $k -ErrorAction Stop
                        }
                    }
                }
                Log-Message -message "Rollback complete." -filePath $LogPath
            } Catch {
                Log-Message -message "WARNING: Rollback failed: $($_.Exception.Message)" -filePath $LogPath
            }
        }
        
        [pscustomobject]@{
            Success  = $false
            UserName = $UserName
            Error    = $err.Trim()
        }
    } Finally {
        $ErrorActionPreference = $oldEAP
    }
}

Function Set-ProfileAcl {
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory)]
        [string]$profileTargetPath,
        # e.g. $profileTargetPath
        [Parameter(Mandatory)]
        [string]$DomainNetbiosName,
        # e.g. 'SSCCLIENT161'
        [Parameter(Mandatory)]
        [string]$User # e.g. 's234083'
    )
    
    # Resolve principals
    $admins = New-Object System.Security.Principal.NTAccount('BUILTIN', 'Administrators')
    $system = New-Object System.Security.Principal.NTAccount('NT AUTHORITY', 'SYSTEM')
    $user = New-Object System.Security.Principal.NTAccount("$DomainNetbiosName\$User")
    
    # Access rule template (OI)(CI) Full Control
    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    
    $principals = @($admins, $user, $system)
    
    # Work the root + all children (skip reparse points to avoid weirdness)
    $items = @()
    $items += Get-Item -LiteralPath $profileTargetPath -ErrorAction Stop
    $items += Get-ChildItem -LiteralPath $profileTargetPath -Recurse -Force -ErrorAction SilentlyContinue -Attributes !ReparsePoint
    
    ForEach ($i In $items) {
        Try {
            If ($PSCmdlet.ShouldProcess($i.FullName, 'Set owner, disable inheritance, grant FullControl')) {
                $acl = Get-Acl -LiteralPath $i.FullName
                
                # Equivalent to: takeown /a
                $acl.SetOwner($admins)
                
                # Equivalent to: icacls /inheritance:r  (disable & remove inherited ACEs)
                $acl.SetAccessRuleProtection($true, $false)
                
                # Equivalent to: icacls /grant X:(OI)(CI)F
                ForEach ($p In $principals) {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($p, $rights, $inherit, $prop, $allow)
                    $acl.SetAccessRule($rule)
                }
                
                Set-Acl -LiteralPath $i.FullName -AclObject $acl
            }
        } Catch {
            Write-Warning "Failed to update '$($i.FullName)': $($_.Exception.Message)"
        }
    }
}

Function Get-NextFreeDriveLetter {
    [CmdletBinding()]
    Param (
        # Letters to never use (defaults to A,B - change if you also want to skip C, etc.)
        [string[]]$Exclude = @(),
        # Pick from Z backward instead of C upward
        [switch]$PreferHigh,
        # Return all free letters instead of just one
        [switch]$AllFree
    )
    
    # Collect used letters (local volumes, removable, optical, network mappings, PSDrives)
    $used = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    
    Try {
        # Win32_LogicalDisk covers fixed/removable/optical/network with letters
        Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
        ForEach-Object { [void]$used.Add($_.DeviceID.TrimEnd(':')) }
    } Catch {
        # Fallback if CIM borks (rare)
        Get-WmiObject Win32_LogicalDisk -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$used.Add($_.DeviceID.TrimEnd(':')) }
    }
    
    # PSDrives (includes mapped network drives that may not show in WMI)
    Get-PSDrive -PSProvider FileSystem |
    Where-Object { $_.Root -match '^[A-Z]:\\$' } |
    ForEach-Object { [void]$used.Add($_.Name) }
    
    # Also include letters reported by Get-Volume (just in case)
    If (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
        Get-Volume | Where-Object DriveLetter |
        ForEach-Object { [void]$used.Add([string]$_.DriveLetter) }
    }
    
    # Build candidate list
    $letters = [char[]]([int][char]'A' .. [int][char]'Z') | ForEach-Object { $_.ToString().ToUpper() }
    If ($PreferHigh) { $letters = $letters[-1 .. - ($letters.Length)] } # reverse
    
    $candidates = $letters | Where-Object { $_ -notin $Exclude -and -not $used.Contains($_) }
    
    If ($AllFree) { Return $candidates }
    
    $next = $candidates | Select-Object -First 1
    If (-not $next) { Throw "No available drive letters found (after excluding: $($Exclude -join ', '))." }
    Return $next
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
	    The path to the log file where the message will be appended. Defaults to 'C:\temp\migration.log'.
	.EXAMPLE
	    Log-Message -message "Process completed successfully"
	    Logs the message with a timestamp to the console and to 'C:\temp\migration.log'.
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
        [string]$filePath = "C:\temp\migration.log"
    )
    $timestamp = [datetime]::Now
    $logEntry = "$timestamp : $message"
    
    Write-Output $logEntry # Writes to standard output
    
    # Ensure the directory exists
    $dir = Split-Path -Path $filePath
    If (-not (Test-Path -Path $dir)) {
        Try {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
            Write-Output "Created directory '$dir'."
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

Function Mount-ProfileVHDX {
    Param (
        [Parameter(Mandatory)]
        [string]$VHDX,
        [char]$NextAvailableDriveLetter,
        [string]$LogPath = "C:\temp\migration.log"
    )
    
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    Try {
        If (-not (Test-Path $VHDX)) {
            Log-Message -message "ERROR: VHDX not found at '$VHDX'." -filePath $LogPath
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'PreCheck';
                Message = "VHDX not found"
            }
        }
        
        Log-Message -message "Mounting disk image: $VHDX" -filePath $LogPath
        Try {
            Mount-DiskImage -ImagePath $VHDX -StorageType VHDX -Access ReadWrite | Out-Null
            Log-Message -message "Mounted: $VHDX" -filePath $LogPath
        } Catch {
            Log-Message -message "ERROR: Failed to mount VHDX '$VHDX' : $($_.Exception.Message)" -filePath $LogPath
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'Mount';
                Message = $_.Exception.Message
            }
        }
        
        # Resolve the disk created by this image
        Try {
            $img = Get-DiskImage -ImagePath $VHDX
            $disk = $img | Get-Disk
            Log-Message -message "Mounted image is Disk Number: $($disk.Number), FriendlyName: $($disk.FriendlyName)" -filePath $LogPath
        } Catch {
            Log-Message -message "ERROR: Could not resolve mounted disk for '$VHDX' : $($_.Exception.Message)" -filePath $LogPath
            # Attempt cleanup
            Try { Dismount-DiskImage -ImagePath $VHDX -ErrorAction Stop } Catch { }
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'ResolveDisk';
                Message = $_.Exception.Message
            }
        }
        
        # Find the volume with Label LIKE 'Profile%'
        Try {
            $profileVols = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop |
            Where-Object { $_.Label -like 'Profile*' -and $_.DeviceID -like "\\?\Volume{*" } |
            Sort-Object -Property DriveLetter # letterless first
        } Catch {
            Log-Message -message "ERROR: Failed querying Win32_Volume : $($_.Exception.Message)" -filePath $LogPath
            Try { Dismount-DiskImage -ImagePath $VHDX -ErrorAction Stop } Catch { }
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'QueryVolume';
                Message = $_.Exception.Message
            }
        }
        
        If (-not $profileVols -or $profileVols.Count -eq 0) {
            Log-Message -message "ERROR: No volumes with Label LIKE 'Profile*' were found on the system after mount." -filePath $LogPath
            Try { Dismount-DiskImage -ImagePath $VHDX -ErrorAction Stop } Catch { }
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'MatchVolume';
                Message = "No 'Profile*' volume found"
            }
        }
        
        # Narrow to those on the newly mounted disk only
        # (Cross-check using the disk's partitions' volume GUIDs)
        $diskPartitions = Get-Partition -DiskNumber $disk.Number
        $diskVolPaths = ForEach ($p In $diskPartitions) {
            Try {
                (Get-Volume -Partition $p).Path | Where-Object { $_ }
            } Catch { }
        }
        
        $candidateVols = $profileVols | Where-Object { $diskVolPaths -contains $_.DeviceID }
        If (-not $candidateVols -or $candidateVols.Count -eq 0) {
            Log-Message -message "ERROR: Found 'Profile*' volumes, but none belong to Disk $($disk.Number)." -filePath $LogPath
            Try { Dismount-DiskImage -ImagePath $VHDX -ErrorAction Stop } Catch { }
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'MatchVolume';
                Message = "No 'Profile*' volume on mounted disk"
            }
        }
        
        If ($candidateVols.Count -gt 1) {
            # Prefer an unlettered one, else fail noisy
            $vol = $candidateVols | Where-Object { -not $_.DriveLetter } | Select-Object -First 1
            If (-not $vol) {
                Log-Message -message "ERROR: Multiple 'Profile*' volumes on the mounted disk and all have drive letters already: $($candidateVols.DriveLetter -join ',')." -filePath $LogPath
                Return [pscustomobject]@{ Success = $false; Stage = 'Disambiguate'; Message = "Multiple matching volumes already assigned" }
            }
        } Else {
            $vol = $candidateVols[0]
        }
        
        # Decide drive letter
        $targetLetter = If ($NextAvailableDriveLetter) { $NextAvailableDriveLetter } ElseIf ($script:NextAvailableDriveLetter) { $script:NextAvailableDriveLetter } Else { Get-NextFreeDriveLetter }
        
        If ($vol.DriveLetter) {
            Log-Message -message "Volume already has drive letter '$($vol.DriveLetter)'. Skipping assignment." -filePath $LogPath
            Return [pscustomobject]@{
                Success     = $true
                Stage       = 'AlreadyAssigned'
                DriveLetter = $vol.DriveLetter
                Volume      = $vol.DeviceID
                Label       = $vol.Label
            }
        }
        
        $driveLetterValue = $targetLetter + ":"
        Log-Message -message "Assigning drive letter '$driveLetterValue' to volume $($vol.DeviceID) (Label='$($vol.Label)')." -filePath $LogPath
        Try {
            # Your original approach using CIM:
            $null = Set-CimInstance -InputObject $vol -Property @{ DriveLetter = $driveLetterValue } -ErrorAction Stop
            Log-Message -message "Assigned drive letter '$driveLetterValue' successfully." -filePath $LogPath
            Return [pscustomobject]@{
                Success     = $true
                Stage       = 'Assigned'
                DriveLetter = $targetLetter
                Volume      = $vol.DeviceID
                Label       = $vol.Label
            }
        } Catch {
            Log-Message -message "ERROR: Failed to assign drive letter '$driveLetterValue' : $($_.Exception.Message)" -filePath $LogPath
            Return [pscustomobject]@{
                Success = $false;
                Stage   = 'AssignLetter';
                Message = $_.Exception.Message
            }
        }
    } Finally {
        $ErrorActionPreference = $oldEAP
    }
}

Function Copy-ProfileWithLogging {
    Param (
        [Parameter(Mandatory)]
        [string]$SourceProfileData,
        [Parameter(Mandatory)]
        [string]$UserProfileDir,
        [Parameter(Mandatory)]
        [string]$DomainNetBiosName,
        [Parameter(Mandatory)]
        [string]$User,
        [string]$LogPath = "C:\temp\migration.log"
    )
    
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    $renamedPath = $null
    
    Try {
        Log-Message -message "Starting profile copy from '$SourceProfileData' to '$UserProfileDir'." -filePath $LogPath
        
        If (-not (Test-Path -Path $SourceProfileData)) {
            Throw "Source path not found: $SourceProfileData"
        }
        
        If (Test-Path -Path $UserProfileDir) {
            $suffix = Get-Date -Format 'yyyyMMdd-HHmmss'
            $renamedPath = "${UserProfileDir}_old_$suffix"
            Log-Message -message "Existing profile folder found. Renaming to '$renamedPath'." -filePath $LogPath
            Rename-Item -Path $UserProfileDir -NewName (Split-Path -Leaf $renamedPath) -ErrorAction Stop
        }
        
        Log-Message -message "Creating target folder '$UserProfileDir'." -filePath $LogPath
        New-Item -Path $UserProfileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        
        Log-Message -message "Setting profile ACLs on '$UserProfileDir' for $DomainNetBiosName\$User." -filePath $LogPath
        Set-ProfileAcl -profileTargetPath $UserProfileDir -DomainNetbiosName $DomainNetBiosName -User $User -ErrorAction Stop
        
        # Run robocopy and inspect its exit code
        $roboLog = Join-Path $env:TEMP ("robocopy_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Log-Message -message "Running robocopy (logging to $roboLog)..." -filePath $LogPath
        
        # NOTE: trailing backslashes matter in robocopy semantics-adjust if you intend "contents of" vs "folder itself"
        $null = & robocopy "$SourceProfileData" "$UserProfileDir" /MIR /XJ /R:1 /W:1 /COPY:DATSO /DCOPY:DAT /TEE /LOG:"$roboLog"
        $rc = $LASTEXITCODE
        
        # By convention, 0-7 are success/info, >=8 is failure.
        If ($rc -ge 8) {
            Throw "Robocopy failed with exit code $rc. See log: $roboLog"
        } Else {
            Log-Message -message "Robocopy completed with exit code $rc. See log: $roboLog" -filePath $LogPath
        }
        
        Log-Message -message "SUCCESS: Copied profile from '$SourceProfileData' to '$UserProfileDir'." -filePath $LogPath
        Return $true
    } Catch {
        $err = $_ | Out-String
        Log-Message -message "ERROR during profile copy: $err" -filePath $LogPath
        
        # Attempt rollback only if we renamed the original
        If ($renamedPath) {
            Try {
                Log-Message -message "Attempting rollback..." -filePath $LogPath
                If (Test-Path -Path $UserProfileDir) {
                    Remove-Item -Path $UserProfileDir -Recurse -Force -ErrorAction Stop
                }
                Rename-Item -Path $renamedPath -NewName (Split-Path -Leaf $UserProfileDir) -ErrorAction Stop
                Log-Message -message "Rollback complete. Restored original folder to '$UserProfileDir'." -filePath $LogPath
            } Catch {
                Log-Message -message "WARNING: Rollback failed: $($_.Exception.Message)" -filePath $LogPath
            }
        }
        
        Return $false
    } Finally {
        $ErrorActionPreference = $oldEAP
    }
}

Function Disable-FSLogixServices {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param (
        [Parameter(Mandatory)]
        [string]$User,
        # e.g. 'DOMAIN\User' or local 'User'
        [string]$LogPath = "C:\temp\migration.log",
        # Also stop services immediately after disabling
        [switch]$StopServices
    )
    
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    # Collector for a quick summary at the end
    $summary = [ordered]@{
        ComputerName     = $env:COMPUTERNAME
        ServicesDisabled = @()
        ServicesStopped  = @()
        ServicesFailed   = @()
        RegistryChanged  = $false
        RegistryError    = $null
        GroupsFound      = @()
        MembersAdded     = @()
        GroupAddFailures = @()
        Success          = $false
    }
    
    Try {
        Log-Message -message "Starting FSLogix disable on $($env:COMPUTERNAME) for user '$User'." -filePath $LogPath
        
        # --- 1) Disable FSLogix services ('frx*') ---
        Try {
            Log-Message -message "Searching for FSLogix services matching 'frx*'..." -filePath $LogPath
            $services = Get-Service -Name 'frx*' -ErrorAction Stop
            
            If (-not $services) {
                Log-Message -message "No FSLogix services found." -filePath $LogPath
            } Else {
                ForEach ($svc In $services) {
                    Try {
                        If ($PSCmdlet.ShouldProcess($svc.Name, "Set StartupType = Disabled")) {
                            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                            $summary.ServicesDisabled += $svc.Name
                            Log-Message -message "Disabled service '$($svc.Name)'." -filePath $LogPath
                        }
                        If ($StopServices -and $svc.Status -ne 'Stopped') {
                            If ($PSCmdlet.ShouldProcess($svc.Name, "Stop-Service")) {
                                Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                                $summary.ServicesStopped += $svc.Name
                                Log-Message -message "Stopped service '$($svc.Name)'." -filePath $LogPath
                            }
                        }
                    } Catch {
                        $summary.ServicesFailed += $svc.Name
                        Log-Message -message "ERROR: Service '$($svc.Name)' operation failed: $($_.Exception.Message)" -filePath $LogPath
                    }
                }
            }
        } Catch {
            # If enumeration itself failed
            $summary.ServicesFailed += 'ServiceEnumeration'
            Log-Message -message "ERROR: Failed to enumerate FSLogix services: $($_.Exception.Message)" -filePath $LogPath
        }
        
        # --- 2) Set Registry: HKLM\SOFTWARE\FSLogix\Profiles\Enabled = 0 ---
        Try {
            $regPathPS = "HKLM:\SOFTWARE\FSLogix\Profiles"
            If (-not (Test-Path $regPathPS)) {
                If ($PSCmdlet.ShouldProcess($regPathPS, "Create registry key")) {
                    Log-Message -message "Creating registry key: $regPathPS" -filePath $LogPath
                    New-Item -Path $regPathPS -Force -ErrorAction Stop | Out-Null
                }
            } Else {
                Log-Message -message "Registry key already exists: $regPathPS" -filePath $LogPath
            }
            
            If ($PSCmdlet.ShouldProcess("$regPathPS\Enabled", "Set DWORD=0")) {
                Set-ItemProperty -Path $regPathPS -Name 'Enabled' -Value 0 -Type DWord -ErrorAction Stop
                $summary.RegistryChanged = $true
                Log-Message -message "Set '$regPathPS\Enabled' = 0." -filePath $LogPath
            }
        } Catch {
            $summary.RegistryError = $_.Exception.Message
            Log-Message -message "ERROR: Failed to set FSLogix registry value: $($summary.RegistryError)" -filePath $LogPath
        }
        
        # --- 3) Add user to any local groups matching '*Exclude List*' ---
        Try {
            Log-Message -message "Searching for local groups matching '*Exclude List*'..." -filePath $LogPath
            $fslogixGroups = Get-LocalGroup | Where-Object { $_.Name -like '*Exclude List*' }
            If (-not $fslogixGroups) {
                Log-Message -message "No local 'Exclude List' groups found." -filePath $LogPath
            } Else {
                ForEach ($grp In $fslogixGroups) {
                    $summary.GroupsFound += $grp.Name
                    Try {
                        If ($PSCmdlet.ShouldProcess("Group '$($grp.Name)'", "Add member '$User'")) {
                            Add-LocalGroupMember -Group $grp.Name -Member $User -ErrorAction Stop
                            $summary.MembersAdded += "$($grp.Name):$User"
                            Log-Message -message "Added '$User' to group '$($grp.Name)'." -filePath $LogPath
                        }
                    } Catch {
                        $summary.GroupAddFailures += "$($grp.Name):$User"
                        Log-Message -message "ERROR: Failed adding '$User' to '$($grp.Name)': $($_.Exception.Message)" -filePath $LogPath
                    }
                }
            }
        } Catch {
            Log-Message -message "ERROR: Failed enumerating local groups: $($_.Exception.Message)" -filePath $LogPath
        }
        
        Log-Message -message "Completed FSLogix disable steps on $($env:COMPUTERNAME)." -filePath $LogPath
        $summary.Success = ($summary.RegistryChanged -and ($summary.ServicesFailed.Count -eq 0))
        [pscustomobject]$summary
    } Catch {
        Log-Message -message "FATAL: Unhandled error: $($_.Exception.Message)" -filePath $LogPath
        $summary.Success = $false
        [pscustomobject]$summary
    } Finally {
        $ErrorActionPreference = $oldEAP
    }
}

Function Clean-ProfileArtifacts {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param (
        [Parameter(Mandatory)]
        [string]$User,
        # e.g. 's234083' (no domain)
        [string]$LogPath = "C:\temp\migration.log",
        # Pattern for deleting stray local profiles under C:\Users
        [string]$LocalProfilePattern = 'local*',
        [switch]$noLocalClean
    )
    
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    # paths we will clean
    $paths = @(
        "C:\Users\$User\AppData\Local\FSLogix",
        "C:\Users\$User\AppData\Local\OneDrive\cache",
        "C:\Users\$User\AppData\Local\Microsoft\Office\16.0\Wef",
        "C:\Users\$User\AppData\Local\Packages\Microsoft.Win32WebViewHost_cw5n1h2txyewy\AC\#!123\INetCache"        
    )
    
    $summary = [ordered]@{
        ComputerName     = $env:COMPUTERNAME
        User             = $User
        ProfileTarget    = "C:\Users\$User"
        DeletedPaths     = @()
        SkippedPaths     = @()
        DeleteErrors     = @()
        DeletedProfiles  = @()
        ProfileDelErrors = @()
        Success          = $false
    }
    
    Try {
        Log-Message -message "Cleaning profile artifacts for '$User' on '$($env:COMPUTERNAME)'." -filePath $LogPath
        
        # --- 1) Remove targeted paths (if present) ---
        ForEach ($p In $paths) {
            Try {
                If (-not (Test-Path -LiteralPath $p)) {
                    Log-Message -message "Path not found, skipping: $p" -filePath $LogPath
                    $summary.SkippedPaths += $p
                    Continue
                }
                
                If ($PSCmdlet.ShouldProcess($p, "Remove-Item -Recurse -Force")) {
                    Log-Message -message "Removing path: $p" -filePath $LogPath
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                    $summary.DeletedPaths += $p
                    Log-Message -message "Removed: $p" -filePath $LogPath
                }
            } Catch {
                $msg = "ERROR removing '$p' : $($_.Exception.Message)"
                Log-Message -message $msg -filePath $LogPath
                $summary.DeleteErrors += $msg
            }
        }
        
        # --- 2) Remove stray local profiles under C:\Users (matching pattern) ---
        If (!($noLocalClean)) {
            Try {
                Log-Message -message "Scanning C:\Users for profiles matching '$LocalProfilePattern'..." -filePath $LogPath
                $candidates = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction Stop |
                Where-Object { $_.Name -like $LocalProfilePattern }
                
                If (-not $candidates) {
                    Log-Message -message "No profiles found matching '$LocalProfilePattern'." -filePath $LogPath
                } Else {
                    ForEach ($dir In $candidates) {
                        Try {
                            If ($PSCmdlet.ShouldProcess($dir.FullName, "Remove-Item -Recurse -Force")) {
                                Log-Message -message "Removing stray profile directory: $($dir.FullName)" -filePath $LogPath
                                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                                $summary.DeletedProfiles += $dir.FullName
                                Log-Message -message "Removed: $($dir.FullName)" -filePath $LogPath
                            }
                        } Catch {
                            $msg = "ERROR removing profile dir '$($dir.FullName)' : $($_.Exception.Message)"
                            Log-Message -message $msg -filePath $LogPath
                            $summary.ProfileDelErrors += $msg
                        }
                    }
                }
            } Catch {
                $msg = "ERROR enumerating C:\Users: $($_.Exception.Message)"
                Log-Message -message $msg -filePath $LogPath
                $summary.ProfileDelErrors += $msg
            }
        } Else {
            $msg = "Bypass local profile cleaning as specified by switch"
            Log-Message -message $msg -filePath $LogPath
        }
        
        
        Log-Message -message "Cleanup complete." -filePath $LogPath
        $summary.Success = ($summary.DeleteErrors.Count -eq 0 -and $summary.ProfileDelErrors.Count -eq 0)
        [pscustomobject]$summary
    } Catch {
        Log-Message -message "FATAL: Unhandled cleanup error: $($_.Exception.Message)" -filePath $LogPath
        $summary.Success = $false
        [pscustomobject]$summary
    } Finally {
        $ErrorActionPreference = $oldEAP
    }
}

Function Set-UserHiveShellFolders {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param (
        [Parameter(Mandatory)]
        [string]$User,
        # sAMAccountName or local username
        [string]$LogPath = "C:\temp\migration.log",
        # Optional overrides
        [string]$UsersRoot = "C:\Users",
        [string]$MountKey = "HKLM\tmp" # temporary mount point for NTUSER.DAT
    )
    
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    
    # Resolved paths/values
    $userProfilePath = Join-Path $UsersRoot $User
    $ntUserDat = Join-Path $userProfilePath "NTUSER.DAT"
    $inetCachePath = Join-Path $userProfilePath "INetCache"
    $tempPath = Join-Path $userProfilePath "Temp"
    
    # Helper: ensure subkey exists, then set value with correct kind
    Function _Set-UserHiveValue {
        Param (
            [Microsoft.Win32.RegistryKey]$BaseKey,
            [string]$SubKeyPath,
            [string]$Name,
            [object]$Value,
            [Microsoft.Win32.RegistryValueKind]$Kind
        )
        $sub = $BaseKey.OpenSubKey($SubKeyPath, $true)
        If (-not $sub) {
            $null = $BaseKey.CreateSubKey($SubKeyPath)
            $sub = $BaseKey.OpenSubKey($SubKeyPath, $true)
        }
        $sub.SetValue($Name, $Value, $Kind)
        $sub.Close()
    }
    
    # Summary object
    $summary = [ordered]@{
        ComputerName  = $env:COMPUTERNAME
        User          = $User
        HiveLoaded    = $false
        ValuesSet     = @()
        OneDriveReset = $false
        Errors        = @()
        Success       = $false
    }
    
    Try {
        # Prechecks
        Log-Message -message "Starting user hive edit for '$User' on $($env:COMPUTERNAME)." -filePath $LogPath
        If (-not (Test-Path -LiteralPath $userProfilePath)) { Throw "Profile path not found: $userProfilePath" }
        If (-not (Test-Path -LiteralPath $ntUserDat)) { Throw "NTUSER.DAT not found: $ntUserDat" }
        
        # If already loaded, try to unload first to avoid stale mounts
        Try {
            If (Test-Path -LiteralPath ("Registry::" + $MountKey.Replace('\', '/'))) {
                Log-Message -message "Existing hive at '$MountKey' detected; attempting unload." -filePath $LogPath
                If ($PSCmdlet.ShouldProcess($MountKey, "reg.exe UNLOAD")) {
                    $null = & reg.exe unload $MountKey 2>&1
                }
            }
        } Catch {
            Log-Message -message "WARNING: Could not unload pre-existing hive '$MountKey': $($_.Exception.Message)" -filePath $LogPath
        }
        
        # Load hive
        Log-Message -message "Loading hive: '$ntUserDat' => '$MountKey'." -filePath $LogPath
        If ($PSCmdlet.ShouldProcess("$ntUserDat", "reg.exe LOAD to $MountKey")) {
            $null = & reg.exe load $MountKey $ntUserDat
            If ($LASTEXITCODE -ne 0) {
                Throw "reg load failed with exit code $LASTEXITCODE."
            }
            $summary.HiveLoaded = $true
        }
        
        # Open 64-bit HKLM base and point to tmp
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        
        # Write values
        Log-Message -message "Setting shell folder and environment values..." -filePath $LogPath
        
        # User Shell Folders (expandable)
        _Set-UserHiveValue -BaseKey $baseKey `
                           -SubKeyPath "tmp\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
                           -Name "Cache" -Value $inetCachePath -Kind ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        $summary.ValuesSet += "User Shell Folders\Cache=$inetCachePath"
        
        # Shell Folders (literal)
        _Set-UserHiveValue -BaseKey $baseKey `
                           -SubKeyPath "tmp\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
                           -Name "Cache" -Value $inetCachePath -Kind ([Microsoft.Win32.RegistryValueKind]::String)
        $summary.ValuesSet += "Shell Folders\Cache=$inetCachePath"
        
        # Environment TEMP/TMP (expandable)
        _Set-UserHiveValue -BaseKey $baseKey `
                           -SubKeyPath "tmp\Environment" `
                           -Name "TEMP" -Value $tempPath -Kind ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        $summary.ValuesSet += "Environment\TEMP=$tempPath"
        
        _Set-UserHiveValue -BaseKey $baseKey `
                           -SubKeyPath "tmp\Environment" `
                           -Name "TMP" -Value $tempPath -Kind ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        $summary.ValuesSet += "Environment\TMP=$tempPath"
        
        $baseKey.Close()
        
        Log-Message -message "User hive updates complete for '$User'." -filePath $LogPath
        $summary.Success = ($summary.Errors.Count -eq 0)
        [pscustomobject]$summary
    } Catch {
        $msg = "FATAL: " + ($_.Exception.Message)
        Log-Message -message $msg -filePath $LogPath
        $summary.Errors += $msg
        $summary.Success = $false
        [pscustomobject]$summary
    } Finally {
        # Always attempt to unload
        Try {
            If ($summary.HiveLoaded -and $PSCmdlet.ShouldProcess($MountKey, "reg.exe UNLOAD")) {
                Log-Message -message "Unloading hive '$MountKey'." -filePath $LogPath
                $null = & reg.exe unload $MountKey 2>&1
                If ($LASTEXITCODE -ne 0) {
                    $em = "reg unload returned exit code $LASTEXITCODE."
                    Log-Message -message "WARNING: $em" -filePath $LogPath
                    $summary.Errors += $em
                }
            }
        } Catch {
            Log-Message -message "WARNING: Failed to unload hive '$MountKey': $($_.Exception.Message)" -filePath $LogPath
            $summary.Errors += "Unload failure: $($_.Exception.Message)"
        }
        
        $ErrorActionPreference = $oldEAP
    }
}

##################################
##           VARS               ##
##################################

$VHDX = "$(Get-FSXStoragePath)\$($env:FSL_DESKTOP_TYPE)\$user\$user.vhdx"
$UserProfilesRoot = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList').ProfilesDirectory)
$UserProfileDir = Join-Path -Path $UserProfilesRoot -ChildPath $user
$DomainNetBiosName = Get-ADDomainNetBIOSName
$NextAvailableDriveLetter = Get-NextFreeDriveLetter
$SourceProfileData = "$($NextAvailableDriveLetter):\Profile"

##################################
##          SCRIPT              ##
##################################

# Logging each value
Log-Message -message "Starting profile conversion..." -filePath $LogPath
Log-Message -message "VHDX path: $VHDX" -filePath $LogPath
Log-Message -message "User profiles root: $UserProfilesRoot" -filePath $LogPath
Log-Message -message "User profile directory: $UserProfileDir" -filePath $LogPath
Log-Message -message "Domain NetBIOS name: $DomainNetBiosName" -filePath $LogPath
Log-Message -message "Next available drive letter: $NextAvailableDriveLetter" -filePath $LogPath
Log-Message -message "Source profile data path: $SourceProfileData" -filePath $LogPath

Mount-ProfileVHDX -VHDX $VHDX -NextAvailableDriveLetter $NextAvailableDriveLetter -LogPath $LogPath

Copy-ProfileWithLogging -SourceProfileData $SourceProfileData -UserProfileDir $UserProfileDir -DomainNetBiosName $DomainNetBiosName -User $User -LogPath $LogPath

Set-UserProfileRegistryEntryFromUser -UserName $user -ProfileTargetPath $UserProfileDir -LogPath $LogPath

Disable-FSLogixServices -LogPath $LogPath -User $user

Clean-ProfileArtifacts -User $user -LogPath $LogPath -noLocalClean

Set-UserHiveShellFolders -User $user -LogPath $LogPath
