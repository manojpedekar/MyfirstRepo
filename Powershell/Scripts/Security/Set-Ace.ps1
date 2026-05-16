<#
	.SYNOPSIS
		A brief description of the Set-Ace.ps1 file.
	
	.DESCRIPTION
		A description of the file.
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
		Created on:   	11/28/2022 10:41 AM
		Created by:   	DT234083
		Organization:
		Filename:
		===========================================================================
#>




$ADGroups = @('Citrix.AdobePro.UK',
	'citrix.windows7.office2010.uk',
	'Citrix.MSVISIO.UK',
	'citrix.msproject.uk',
	'citrix.windows7.office2010.uk',
	'uklegal_dept')



$ADMembers = $ADGroups | ForEach-Object { (get-adgroup $_ -server globeop.com -Properties members).members } | Where-Object { $_ -notlike "CN=S-1-5*" } | Get-ADUser -Server globeop.com -Properties HomeDirectory
$ADMembers | Where-Object { $_.enabled -eq $true -and $_.homeDirectory -ne $null } | Select-Object Name, samAccountName, Enabled, HomeDirectory


$UsersToUpdate = Import-Csv c:\temp\GlobeOp_HomeDrive_ACL_Update_test.csv

$UsersToUpdate = Import-Csv c:\temp\GlobeOp_HomeDrive_ACL_Update.csv

$i=0
$Count = $UsersToUpdate.count













ForEach ($UserToUpdate In $UsersToUpdate) {
	$i++
	Write-Progress -Activity "Updating ACLs $($i/$count)" -PercentComplete ($i/$count) -CurrentOperation $($UserToUpdate.Name)
	$ACL = Get-Acl $UserToUpdate.HomeDirectory
	
	# Create the ACE
	$identity = $UserToUpdate.CorpUser
	$rights = 'FullControl' #Other options: [enum]::GetValues('System.Security.AccessControl.FileSystemRights')
	$inheritance = 'ContainerInherit, ObjectInherit' #Other options: [enum]::GetValues('System.Security.AccessControl.Inheritance')
	$propagation = 'None' #Other options: [enum]::GetValues('System.Security.AccessControl.PropagationFlags')
	$type = 'Allow' #Other options: [enum]::GetValues('System.Securit y.AccessControl.AccessControlType')
	$ACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
	
	$ACL.AddAccessRule($ACE)
	
	Set-Acl -path $UserToUpdate.HomeDirectory -AclObject $acl
}





Function Take-FolderOwnership {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Directory,
        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )
    
    Begin {
        $Group = New-Object System.Security.Principal.NTAccount("Builtin", "Administrators")
    }
    
    Process {
        ForEach ($Folder In $Directory) {
            # Get folders to process
            If ($Recurse) {
                Write-Verbose "Collecting subfolders."
                $FoldersToProcess = Get-ChildItem -Path $Folder -Directory -Recurse -Force -ErrorAction SilentlyContinue
                # Include the root folder
                $FoldersToProcess = @(Get-Item $Folder) + $FoldersToProcess
            } Else {
                $FoldersToProcess = @(Get-Item $Folder)
            }
            
            # Process each folder
            ForEach ($Item In $FoldersToProcess) {
                Try {
                    $acl = Get-Acl -Path $Item.FullName
                    
                    # Check if owner is already Administrators
                    If ($acl.Owner -eq $Group.Value) {
                        Write-Verbose "Skipping (already owned by Administrators): $($Item.FullName)"
                        Continue
                    }
                    
                    $acl.SetOwner($Group)
                    Set-Acl -Path $Item.FullName -AclObject $acl
                    Write-Verbose "Successfully took ownership of: $($Item.FullName)"
                } Catch {
                    Write-Warning "Failed to take ownership of $($Item.FullName): $_"
                }
            }
        }
    }
}

# Usage examples:
# Take-FolderOwnership -Directory "C:\SomeFolder"
# Take-FolderOwnership -Directory "C:\SomeFolder" -Recurse
# Take-FolderOwnership -Directory "C:\Folder1", "C:\Folder2" -Recurse -Verbose






$results = Get-ChildItem D:\sschome\ -Recurse -Directory -ErrorAction SilentlyContinue -ErrorVariable $DirError | get-acl | Where-Object { $_.AreAccessRulesProtected -eq $true } | Select-Object @{ Name = "Path"; Expression = { Convert-Path $_.Path } }, AreAccessRulesProtected











$HomeDir = "D:\Home6"
$ACL = Get-Acl $HomeDir

# Create the ACE
$type = 'Allow' #Other options: [enum]::GetValues('System.Securit y.AccessControl.AccessControlType')
$inheritance = 'None' #Other options: [enum]::GetValues('System.Security.AccessControl.Inheritance')
$propagation = 'None' #Other options: [enum]::GetValues('System.Security.AccessControl.PropagationFlags')

$FCACE = New-Object System.Security.AccessControl.FileSystemAccessRule("GLOBEOP\perm-mum2flsprd6-fs-Home6-FC", 'FullControl', $inheritance, $propagation, $type)
$RWACE = New-Object System.Security.AccessControl.FileSystemAccessRule("GLOBEOP\perm-mum2flsprd6-fs-Home6-RW", 'WriteExtendedAttributes, WriteAttributes, ReadAndExecute, Synchronize', $inheritance, $propagation, $type)

$ACL.AddAccessRule($FCACE)
$ACL.AddAccessRule($RWACE)


Start-Job -ArgumentList $HomeDir, $ACL -ScriptBlock { Param ($p1, $p2) Set-Acl -Path $p1 -AclObject $p2 } -Name Home3_ACL


Start-Job -ScriptBlock { Set-Acl -path $HomeDir -AclObject $acl } -Name Home2_acl


Start-Job -




Function Add-FolderPermission {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Directory,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $false)]
        [System.Security.AccessControl.FileSystemRights]$Rights = "FullControl",
        [Parameter(Mandatory = $false)]
        [System.Security.AccessControl.AccessControlType]$AccessType = "Allow",
        [Parameter(Mandatory = $false)]
        [System.Security.AccessControl.InheritanceFlags]$Inheritance = "ContainerInherit, ObjectInherit",
        [Parameter(Mandatory = $false)]
        [System.Security.AccessControl.PropagationFlags]$Propagation = "None"
    )
    
    Process {
        ForEach ($Folder In $Directory) {
            Try {
                # Get current ACL
                $acl = Get-Acl -Path $Folder
                
                # Create the access rule
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $Identity,
                    $Rights,
                    $Inheritance,
                    $Propagation,
                    $AccessType
                )
                
                # Add the rule to ACL
                $acl.AddAccessRule($accessRule)
                
                # Apply the ACL (this applies to subfolders and files due to inheritance flags)
                Set-Acl -Path $Folder -AclObject $acl
                
                Write-Verbose "Successfully added $AccessType $Rights permission for $Identity to: $Folder"
                Write-Verbose "Inheritance applies to all subfolders and files"
                
            } Catch {
                Write-Warning "Failed to add permission to $Folder : $_"
            }
        }
    }
}

# Usage examples:

# Add SYSTEM with Full Control (matching your screenshot)
#Add-FolderPermission -Directory "C:\MyFolder" -Identity "SYSTEM" -Verbose

# Add a specific user with Modify rights
#Add-FolderPermission -Directory "C:\MyFolder" -Identity "DOMAIN\Username" -Rights "Modify"

# Add multiple folders at once
#Add-FolderPermission -Directory "C:\Folder1", "C:\Folder2" -Identity "SYSTEM" -Verbose

# Custom permissions example
#Add-FolderPermission -Directory "C:\MyFolder" -Identity "Users" -Rights "ReadAndExecute"





Function Test-FolderPermission {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Path,
        [Parameter(Mandatory = $false)]
        [string]$Identity = "SYSTEM",
        [Parameter(Mandatory = $false)]
        [System.Security.AccessControl.FileSystemRights]$Rights = "FullControl",
        [Parameter(Mandatory = $false)]
        [System.Security.AccessControl.AccessControlType]$AccessType = "Allow"
    )
    
    Process {
        ForEach ($Item In $Path) {
            Try {
                # Get the ACL
                Try {
                    $acl = Get-Acl -Path $Item -erroraction Stop
                } Catch {
                throw "Can not access folder"    
                }
                
                
                # Get all access rules for the specified identity
                $accessRules = $acl.Access | Where-Object {
                    $_.IdentityReference -like "*$Identity*" -and
                    $_.AccessControlType -eq $AccessType
                }
                
                # Check if any rule grants the required rights
                $hasPermission = $false
                ForEach ($rule In $accessRules) {
                    # Check if the rule contains all the required rights
                    If (($rule.FileSystemRights -band $Rights) -eq $Rights) {
                        $hasPermission = $true
                        Write-Verbose "Found matching permission: $($rule.IdentityReference) has $($rule.FileSystemRights)"
                        Break
                    }
                }
                
                # Create result object
                [PSCustomObject]@{
                    Path          = $Item
                    Identity      = $Identity
                    Rights        = $Rights
                    HasPermission = $hasPermission
                    AccessType    = $AccessType
                }
                
                If ($hasPermission) {
                    Write-Verbose "$Identity has $Rights on: $Item"
                } Else {
                    Write-Verbose "$Identity does NOT have $Rights on: $Item"
                }
                
            } Catch {
                Write-Warning "Failed to check permissions on $Item : $_"
                [PSCustomObject]@{
                    Path          = $Item
                    Identity      = $Identity
                    Rights        = $Rights
                    HasPermission = $false
                    AccessType    = $AccessType
                    Error         = $_.Exception.Message
                }
            }
        }
    }
}

# Usage examples:

# Test if SYSTEM has FullControl (default)
Test-FolderPermission -Path "C:\MyFolder" -Verbose

# Test multiple paths
Test-FolderPermission -Path "C:\Folder1", "C:\Folder2"

# Test different identity and rights
Test-FolderPermission -Path "C:\MyFolder" -Identity "Administrators" -Rights "Modify"



# Use in a conditional
Function validate-folder {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Folder
    )
    
    Try {
        $result = Test-FolderPermission -Path $folder -ErrorAction Stop
    } Catch {
        Write-host "$Folder" -ForegroundColor Red
        return 
    }
    
    If ($result.HasPermission) {
        Write-Host "SYSTEM has Full Control!"
    } Else {
        Write-Host "SYSTEM does NOT have Full Control. Adding Access"
        Add-FolderPermission -Directory $folder -Identity "SYSTEM" -Verbose
    }
    
}
# Check multiple folders and filter results
$folders = "C:\Folder1", "C:\Folder2", "C:\Folder3"
$results = Test-FolderPermission -Path $folders
$results | Where-Object { -not $_.HasPermission } | Format-Table -AutoSize





Try {
    $acl = Get-Acl -Path $Folder -ErrorAction Stop
} Catch {
    Write-Warning "Cannot access $Folder : $_"
}







Function Get-RegistryShare {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [string]$ShareName
    )
    
    Begin {
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares"
    }
    
    Process {
        Try {
            # Check if registry path exists
            If (-not (Test-Path -Path $registryPath)) {
                Write-Warning "Registry path not found: $registryPath"
                Return
            }
            
            # Get all share properties
            $shares = Get-ItemProperty -Path $registryPath -ErrorAction Stop
            
            # Get list of share names (exclude PS properties)
            $shareNames = $shares.PSObject.Properties |
            Where-Object { $_.Name -notlike "PS*" } |
            Select-Object -ExpandProperty Name
            
            # Filter by specific share if requested
            If ($ShareName) {
                $shareNames = $shareNames | Where-Object { $_ -eq $ShareName }
                If (-not $shareNames) {
                    Write-Warning "Share '$ShareName' not found in registry"
                    Return
                }
            }
            
            # Process each share
            $results = @()
            ForEach ($name In $shareNames) {
                Try {
                    # Get the multi-string value for the share
                    $shareData = $shares.$name
                    
                    # Parse the share data
                    $shareInfo = @{
                        ShareName      = $name
                        Path           = $null
                        Remark         = $null
                        Type           = $null
                        MaxUses        = $null
                        CSCFlags       = $null
                        PathExists     = $false
                        PathAccessible = $false
                    }
                    
                    # Parse each line of the share data
                    ForEach ($line In $shareData) {
                        If ($line -match '^Path=(.+)$') {
                            $shareInfo.Path = $matches[1]
                        } ElseIf ($line -match '^Remark=(.*)$') {
                            $shareInfo.Remark = $matches[1]
                        } ElseIf ($line -match '^Type=(.+)$') {
                            $shareInfo.Type = $matches[1]
                        } ElseIf ($line -match '^MaxUses=(.+)$') {
                            $shareInfo.MaxUses = $matches[1]
                        } ElseIf ($line -match '^CSCFlags=(.+)$') {
                            $shareInfo.CSCFlags = $matches[1]
                        }
                    }
                    
                    # Test if path exists and is accessible
                    If ($shareInfo.Path) {
                        $shareInfo.PathExists = Test-Path -Path $shareInfo.Path -ErrorAction SilentlyContinue
                        
                        # Try to access the path
                        If ($shareInfo.PathExists) {
                            Try {
                                $null = Get-Item -Path $shareInfo.Path -ErrorAction Stop
                                $shareInfo.PathAccessible = $true
                            } Catch {
                                $shareInfo.PathAccessible = $false
                                Write-Verbose "Path exists but is not accessible: $($shareInfo.Path)"
                            }
                        } Else {
                            Write-Verbose "Path does not exist: $($shareInfo.Path)"
                        }
                    }
                    
                    # Create output object
                    $results += [PSCustomObject]$shareInfo
                    
                } Catch {
                    Write-Warning "Failed to process share '$name': $_"
                }
            }
            
            Return $results
            
        } Catch {
            Write-Warning "Failed to read registry shares: $_"
        }
    }
}

# Usage examples:

# Get all shares with path validation
Get-RegistryShare | Format-Table -AutoSize

# Get specific share
Get-RegistryShare -ShareName "MyShare"

# Find shares with missing paths
Get-RegistryShare | Where-Object { -not $_.PathExists } | Format-Table -AutoSize

# Find shares with inaccessible paths
Get-RegistryShare | Where-Object { $_.PathExists -and -not $_.PathAccessible }

# Export to CSV
Get-RegistryShare | Export-Csv -Path "C:\temp\shares.csv" -NoTypeInformation

# Verbose output
Get-RegistryShare -Verbose



