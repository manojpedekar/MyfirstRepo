Function New-PortfolioManagerADGroups {
    <#
    .SYNOPSIS
        Creates Active Directory groups for a Portfolio Manager with proper permissions structure.
    
    .DESCRIPTION
        Creates file share permission groups and a role group for a new Portfolio Manager,
        then configures the appropriate group memberships.
    
    .PARAMETER UserName
        The username of the Portfolio Manager for whom groups should be created.
    
    .EXAMPLE
        New-PortfolioManagerADGroups -UserName "jsmith"
        Creates all required AD groups for user jsmith with appropriate memberships.
    
    .NOTES
        Requires Active Directory PowerShell module and appropriate permissions to create groups.
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true,
                   HelpMessage = "Enter the username for the Portfolio Manager")]
        [ValidateNotNullOrEmpty()]
        [string]$UserName
    )
    
    Begin {
        # Import Active Directory module
        If (-not (Get-Module -Name ActiveDirectory)) {
            Try {
                Import-Module ActiveDirectory -ErrorAction Stop
                Write-Verbose "Active Directory module loaded successfully"
            } Catch {
                Write-Error "Failed to import Active Directory module: $_"
                Return
            }
        }
        
        # Define OUs
        $FileShareOU = "OU=FileShare,OU=Permissions,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global"
        $RolesOU = "OU=Lighthouse,OU=Roles,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global"
        
        # Define domain
        $Domain = "sscclient161.ssncad.global"
    }
    
    Process {
        $NewUserName = $UserName
        
        Write-Host "Creating Portfolio Manager AD groups for user: $NewUserName" -ForegroundColor Cyan
        Write-Host ("=" * 70) -ForegroundColor Cyan
        
        Try {
            # Verify user exists
            Write-Verbose "Verifying user $NewUserName exists..."
            $ADUser = Get-ADUser -Identity $NewUserName -ErrorAction Stop
            Write-Host "✓ User verified: $($ADUser.DistinguishedName)" -ForegroundColor Green
        } Catch {
            Write-Error "User '$NewUserName' not found in Active Directory: $_"
            Return
        }
        
        # Define group names
        $PermGroupRO = "perm-lipfs1-PenglaiPeak-Shared-$NewUserName-ro"
        $PermGroupRW = "perm-lipfs1-PenglaiPeak-Shared-$NewUserName-rw"
        $PermGroupFC = "perm-lipfs1-PenglaiPeak-Shared-$NewUserName-fc"
        $RoleGroup = "Role-PenglaiPeak-Portfoliomgr-$NewUserName"
        
        $GroupDescription = "Access for \\lipfs1\penglaipeakshared\$NewUserName"
        $RoleDescription = "PenglaiPeak portfolio management for $NewUserName"
        
        # ====================================================================
        # STEP 1: Create File Share Permission Groups (Domain Local)
        # ====================================================================
        Write-Host "`n[1/4] Creating file share permission groups..." -ForegroundColor Yellow
        
        $FileShareGroups = @(
            @{ Name = $PermGroupRO; Description = $GroupDescription },
            @{ Name = $PermGroupRW; Description = $GroupDescription },
            @{ Name = $PermGroupFC; Description = $GroupDescription }
        )
        
        ForEach ($group In $FileShareGroups) {
            Try {
                If (Get-ADGroup -Filter "Name -eq '$($group.Name)'" -ErrorAction SilentlyContinue) {
                    Write-Warning "Group '$($group.Name)' already exists, skipping creation"
                } Else {
                    If ($PSCmdlet.ShouldProcess($group.Name, "Create Domain Local Security Group")) {
                        New-ADGroup -Name $group.Name `
                                    -SamAccountName $group.Name `
                                    -GroupCategory Security `
                                    -GroupScope DomainLocal `
                                    -DisplayName $group.Name `
                                    -Path $FileShareOU `
                                    -Description $group.Description `
                                    -ErrorAction Stop
                        Write-Host "  ✓ Created: $($group.Name)" -ForegroundColor Green
                    }
                }
            } Catch {
                Write-Error "Failed to create group '$($group.Name)': $_"
                Return
            }
        }
        
        # ====================================================================
        # STEP 2: Create Role Group (Global)
        # ====================================================================
        Write-Host "`n[2/4] Creating role group..." -ForegroundColor Yellow
        
        Try {
            If (Get-ADGroup -Filter "Name -eq '$RoleGroup'" -ErrorAction SilentlyContinue) {
                Write-Warning "Group '$RoleGroup' already exists, skipping creation"
            } Else {
                If ($PSCmdlet.ShouldProcess($RoleGroup, "Create Global Security Group")) {
                    New-ADGroup -Name $RoleGroup `
                                -SamAccountName $RoleGroup `
                                -GroupCategory Security `
                                -GroupScope Global `
                                -DisplayName $RoleGroup `
                                -Path $RolesOU `
                                -Description $RoleDescription `
                                -ErrorAction Stop
                    Write-Host "  ✓ Created: $RoleGroup" -ForegroundColor Green
                }
            }
        } Catch {
            Write-Error "Failed to create role group '$RoleGroup': $_"
            Return
        }
        
        # Small delay to ensure groups are replicated
        Start-Sleep -Seconds 2
        
        # ====================================================================
        # STEP 3: Configure Role Group Memberships
        # ====================================================================
        Write-Host "`n[3/4] Configuring role group memberships..." -ForegroundColor Yellow
        
        # Add user as member of Role group
        Try {
            If ($PSCmdlet.ShouldProcess("$RoleGroup", "Add member $NewUserName")) {
                Add-ADGroupMember -Identity $RoleGroup -Members $NewUserName -ErrorAction Stop
                Write-Host "  ✓ Added $NewUserName as member of $RoleGroup" -ForegroundColor Green
            }
        } Catch {
            Write-Error "Failed to add $NewUserName to $RoleGroup : $_"
        }
        
        # Add Role group as member of existing groups
        $RoleGroupMemberships = @(
            "CN=perm-lipfs-PenglaiPeak-Shared-ro,OU=FileShare,OU=Permissions,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global",
            "CN=perm-lipfs1-SData-ro,OU=FileShare,OU=Permissions,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global"
        )
        
        ForEach ($groupDN In $RoleGroupMemberships) {
            Try {
                If ($PSCmdlet.ShouldProcess($groupDN, "Add $RoleGroup as member")) {
                    Add-ADGroupMember -Identity $groupDN -Members $RoleGroup -ErrorAction Stop
                    Write-Host "  ✓ Added $RoleGroup to $groupDN" -ForegroundColor Green
                }
            } Catch {
                Write-Warning "Failed to add $RoleGroup to $groupDN : $_"
            }
        }
        
        # ====================================================================
        # STEP 4: Configure Permission Group Memberships
        # ====================================================================
        Write-Host "`n[4/4] Configuring permission group memberships..." -ForegroundColor Yellow
        
        # Add members to RO permission group
        $ROMembers = @(
            "CN=Role-lipfs-PenglaiPeak-Shared-Compliance-ro,OU=Lighthouse,OU=Roles,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global",
            "CN=role-lhcompliance,OU=Lighthouse,OU=Roles,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global"
        )
        
        Write-Host "`n  Configuring $PermGroupRO members:" -ForegroundColor Cyan
        ForEach ($memberDN In $ROMembers) {
            Try {
                If ($PSCmdlet.ShouldProcess($PermGroupRO, "Add member $memberDN")) {
                    Add-ADGroupMember -Identity $PermGroupRO -Members $memberDN -ErrorAction Stop
                    Write-Host "    ✓ Added member: $memberDN" -ForegroundColor Green
                }
            } Catch {
                Write-Warning "Failed to add member to $PermGroupRO : $_"
            }
        }
        
        # Add members to RW permission group
        $RWMembers = @(
            $RoleGroup,
            "CN=Role-PenglaiPeak-Shared-Manager,OU=Lighthouse,OU=Roles,OU=Domain Groups,DC=sscclient161,DC=ssncad,DC=global"
        )
        
        Write-Host "`n  Configuring $PermGroupRW members:" -ForegroundColor Cyan
        ForEach ($member In $RWMembers) {
            Try {
                If ($PSCmdlet.ShouldProcess($PermGroupRW, "Add member $member")) {
                    Add-ADGroupMember -Identity $PermGroupRW -Members $member -ErrorAction Stop
                    Write-Host "    ✓ Added member: $member" -ForegroundColor Green
                }
            } Catch {
                Write-Warning "Failed to add member to $PermGroupRW : $_"
            }
        }
        
        # ====================================================================
        # SUMMARY
        # ====================================================================
        Write-Host "`n" -NoNewline
        Write-Host ("=" * 70) -ForegroundColor Cyan
        Write-Host "Portfolio Manager AD Groups Setup Complete!" -ForegroundColor Green
        Write-Host ("=" * 70) -ForegroundColor Cyan
        
        Write-Host "`nCreated Groups:" -ForegroundColor Yellow
        Write-Host "  • $PermGroupRO (Domain Local)" -ForegroundColor White
        Write-Host "  • $PermGroupRW (Domain Local)" -ForegroundColor White
        Write-Host "  • $PermGroupFC (Domain Local)" -ForegroundColor White
        Write-Host "  • $RoleGroup (Global)" -ForegroundColor White
        
        Write-Host "`nMembership Summary:" -ForegroundColor Yellow
        Write-Host "  User Membership:" -ForegroundColor Cyan
        Write-Host "    • $NewUserName → $RoleGroup" -ForegroundColor White
        
        Write-Host "`n  Role Group Memberships:" -ForegroundColor Cyan
        Write-Host "    • $RoleGroup → perm-lipfs-PenglaiPeak-Shared-ro" -ForegroundColor White
        Write-Host "    • $RoleGroup → perm-lipfs1-SData-ro" -ForegroundColor White
        Write-Host "    • $RoleGroup → $PermGroupRW" -ForegroundColor White
        
        Write-Host "`n  Permission Group Members:" -ForegroundColor Cyan
        Write-Host "    • $PermGroupRO contains compliance roles" -ForegroundColor White
        Write-Host "    • $PermGroupRW contains $RoleGroup and managers" -ForegroundColor White
        Write-Host "    • $PermGroupFC (no members configured)" -ForegroundColor White
        
        Write-Host ""
    }
}

Function New-PortfolioManagerFolder {
    <#
    .SYNOPSIS
        Creates a Portfolio Manager folder with specific ACL permissions.
    
    .DESCRIPTION
        Creates a new folder for a Portfolio Manager in the PenglaiPeak shared location
        and applies appropriate NTFS permissions including read-only, read-write, and
        full control groups.
    
    .PARAMETER UserName
        The username of the Portfolio Manager for whom the folder should be created.
    
    .PARAMETER BasePath
        The base path where the folder will be created. 
        Default: \\sscclient161.ssncad.global\internal-us\sdata\PenglaiPeakShared
    
    .EXAMPLE
        New-PortfolioManagerFolder -UserName "jsmith"
        Creates folder \\sscclient161.ssncad.global\internal-us\sdata\PenglaiPeakShared\jsmith
    
    .EXAMPLE
        New-PortfolioManagerFolder -UserName "jsmith" -Verbose
        Creates the folder with verbose output showing each ACL entry being applied.
    
    .NOTES
        Requires:
        - Appropriate permissions to create folders and modify ACLs on the target share
        - The permission groups must exist before running this function
        - Run from a system with access to the target UNC path
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true,
                   HelpMessage = "Enter the username for the Portfolio Manager")]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath = "\\sscclient161.ssncad.global\internal-us\sdata\PenglaiPeakShared"
    )
    
    Begin {
        Write-Verbose "Initializing New-PortfolioManagerFolder function"
        
        # Define domain
        $Domain = "sscclient161"
    }
    
    Process {
        $NewUserName = $UserName
        $FolderPath = Join-Path -Path $BasePath -ChildPath $NewUserName
        
        Write-Host "Creating Portfolio Manager folder for user: $NewUserName" -ForegroundColor Cyan
        Write-Host ("=" * 70) -ForegroundColor Cyan
        Write-Host "Target Path: $FolderPath" -ForegroundColor White
        Write-Host ""
        
        # ====================================================================
        # STEP 1: Verify Base Path Exists
        # ====================================================================
        Write-Host "[1/4] Verifying base path accessibility..." -ForegroundColor Yellow
        
        If (-not (Test-Path -Path $BasePath)) {
            Write-Error "Base path '$BasePath' does not exist or is not accessible."
            Write-Error "Please verify network connectivity and permissions."
            Return
        }
        Write-Host "  ✓ Base path accessible: $BasePath" -ForegroundColor Green
        
        # ====================================================================
        # STEP 2: Create Folder
        # ====================================================================
        Write-Host "`n[2/4] Creating folder..." -ForegroundColor Yellow
        
        If (Test-Path -Path $FolderPath) {
            Write-Warning "Folder '$FolderPath' already exists."
            $continue = Read-Host "Do you want to update permissions on the existing folder? (Y/N)"
            If ($continue -ne 'Y') {
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                Return
            }
        } Else {
            Try {
                If ($PSCmdlet.ShouldProcess($FolderPath, "Create folder")) {
                    New-Item -Path $FolderPath -ItemType Directory -ErrorAction Stop | Out-Null
                    Write-Host "  ✓ Folder created: $FolderPath" -ForegroundColor Green
                }
            } Catch {
                Write-Error "Failed to create folder '$FolderPath': $_"
                Return
            }
        }
        
        # ====================================================================
        # STEP 3: Disable Inheritance and Remove Existing Permissions
        # ====================================================================
        Write-Host "`n[3/4] Configuring ACL - Disabling inheritance..." -ForegroundColor Yellow
        
        Try {
            # Get current ACL
            $acl = Get-Acl -Path $FolderPath
            
            # Disable inheritance and remove inherited permissions
            If ($PSCmdlet.ShouldProcess($FolderPath, "Disable ACL inheritance")) {
                $acl.SetAccessRuleProtection($true, $false)
                Write-Host "  ✓ Inheritance disabled" -ForegroundColor Green
                
                # Remove all existing access rules
                $acl.Access | ForEach-Object {
                    $acl.RemoveAccessRule($_) | Out-Null
                }
                Write-Host "  ✓ Existing permissions removed" -ForegroundColor Green
            }
        } Catch {
            Write-Error "Failed to modify ACL inheritance: $_"
            Return
        }
        
        # ====================================================================
        # STEP 4: Set Owner
        # ====================================================================
        Write-Host "`n  Setting owner..." -ForegroundColor Cyan
        
        Try {
            If ($PSCmdlet.ShouldProcess($FolderPath, "Set owner to BUILTIN\Administrators")) {
                $adminGroup = New-Object System.Security.Principal.NTAccount("BUILTIN\Administrators")
                $acl.SetOwner($adminGroup)
                Write-Host "    ✓ Owner set: BUILTIN\Administrators" -ForegroundColor Green
            }
        } Catch {
            Write-Warning "Failed to set owner: $_"
        }
        
        # ====================================================================
        # STEP 5: Add ACL Entries
        # ====================================================================
        Write-Host "`n  Adding ACL entries..." -ForegroundColor Cyan
        
        # Define ACL entries
        $aclEntries = @(
            @{
                Identity    = "NT AUTHORITY\SYSTEM"
                Rights      = "FullControl"
                Type        = "Allow"
                Inheritance = "ContainerInherit, ObjectInherit"
                Propagation = "None"
            },
            @{
                Identity    = "BUILTIN\Administrators"
                Rights      = "FullControl"
                Type        = "Allow"
                Inheritance = "ContainerInherit, ObjectInherit"
                Propagation = "None"
            },
            @{
                Identity = "$Domain\perm-lipfs1-PenglaiPeak-Shared-$NewUserName-ro"
                Rights   = "ReadAndExecute, Synchronize"
                Type     = "Allow"
                Inheritance = "ContainerInherit, ObjectInherit"
                Propagation = "None"
            },
            @{
                Identity = "$Domain\perm-lipfs1-PenglaiPeak-Shared-$NewUserName-rw"
                Rights   = "DeleteSubdirectoriesAndFiles, Modify, Synchronize"
                Type     = "Allow"
                Inheritance = "ContainerInherit, ObjectInherit"
                Propagation = "None"
            },
            @{
                Identity = "$Domain\perm-lipfs1-PenglaiPeak-Shared-$NewUserName-fc"
                Rights   = "FullControl"
                Type     = "Allow"
                Inheritance = "ContainerInherit, ObjectInherit"
                Propagation = "None"
            }
        )
        
        ForEach ($entry In $aclEntries) {
            Try {
                If ($PSCmdlet.ShouldProcess($entry.Identity, "Add ACL entry with $($entry.Rights)")) {
                    # Parse inheritance flags
                    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]$entry.Inheritance
                    
                    # Parse propagation flags
                    $propagationFlags = [System.Security.AccessControl.PropagationFlags]$entry.Propagation
                    
                    # Parse file system rights
                    $fileSystemRights = [System.Security.AccessControl.FileSystemRights]$entry.Rights
                    
                    # Create access rule
                    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $entry.Identity,
                        $fileSystemRights,
                        $inheritanceFlags,
                        $propagationFlags,
                        $entry.Type
                    )
                    
                    # Add the access rule
                    $acl.AddAccessRule($accessRule)
                    Write-Host "    ✓ Added: $($entry.Identity) - $($entry.Rights)" -ForegroundColor Green
                }
            } Catch {
                Write-Error "Failed to add ACL entry for $($entry.Identity): $_"
                Return
            }
        }
        
        # ====================================================================
        # STEP 6: Apply ACL to Folder
        # ====================================================================
        Write-Host "`n  Applying ACL to folder..." -ForegroundColor Cyan
        
        Try {
            If ($PSCmdlet.ShouldProcess($FolderPath, "Apply ACL")) {
                Set-Acl -Path $FolderPath -AclObject $acl -ErrorAction Stop
                Write-Host "    ✓ ACL applied successfully" -ForegroundColor Green
            }
        } Catch {
            Write-Error "Failed to apply ACL: $_"
            Return
        }
        
        # ====================================================================
        # STEP 7: Verify Permissions
        # ====================================================================
        Write-Host "`n[4/4] Verifying permissions..." -ForegroundColor Yellow
        
        Try {
            $verifyAcl = Get-Acl -Path $FolderPath
            
            Write-Host "`n  Owner: $($verifyAcl.Owner)" -ForegroundColor White
            Write-Host "`n  Access Rules:" -ForegroundColor White
            
            $verifyAcl.Access | ForEach-Object {
                $rightsDisplay = $_.FileSystemRights
                $identityDisplay = $_.IdentityReference
                $typeDisplay = $_.AccessControlType
                
                Write-Host "    • $identityDisplay" -ForegroundColor Cyan
                Write-Host "      Rights: $rightsDisplay ($typeDisplay)" -ForegroundColor Gray
                Write-Host "      Inherited: $($_.IsInherited)" -ForegroundColor Gray
            }
        } Catch {
            Write-Warning "Could not verify permissions: $_"
        }
        
        # ====================================================================
        # SUMMARY
        # ====================================================================
        Write-Host "`n" -NoNewline
        Write-Host ("=" * 70) -ForegroundColor Cyan
        Write-Host "Portfolio Manager Folder Setup Complete!" -ForegroundColor Green
        Write-Host ("=" * 70) -ForegroundColor Cyan
        
        Write-Host "`nFolder Details:" -ForegroundColor Yellow
        Write-Host "  Path: $FolderPath" -ForegroundColor White
        Write-Host "  Owner: BUILTIN\Administrators" -ForegroundColor White
        
        Write-Host "`nPermissions Applied:" -ForegroundColor Yellow
        Write-Host "  • SYSTEM - Full Control" -ForegroundColor White
        Write-Host "  • Administrators - Full Control" -ForegroundColor White
        Write-Host "  • perm-lipfs1-PenglaiPeak-Shared-$NewUserName-ro - Read & Execute" -ForegroundColor White
        Write-Host "  • perm-lipfs1-PenglaiPeak-Shared-$NewUserName-rw - Modify" -ForegroundColor White
        Write-Host "  • perm-lipfs1-PenglaiPeak-Shared-$NewUserName-fc - Full Control" -ForegroundColor White
        
        Write-Host "`nNext Steps:" -ForegroundColor Yellow
        Write-Host "  1. Verify the folder is accessible to the appropriate users" -ForegroundColor White
        Write-Host "  2. Test permissions with a member of each permission group" -ForegroundColor White
        Write-Host "  3. Document the folder location for the portfolio manager" -ForegroundColor White
        Write-Host ""
        
        # Return folder path for pipeline usage
        Return $FolderPath
    }
}


