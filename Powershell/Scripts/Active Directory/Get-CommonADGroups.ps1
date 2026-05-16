Function Get-CommonADGroups {
    <#
    .SYNOPSIS
        Finds AD groups common to all specified users and lists additional members.
    
    .DESCRIPTION
        Takes a list of AD user samAccountNames and queries a specified domain controller
        to find groups that are common to all users. Also identifies any additional users
        who are members of these common groups. Excludes default domain groups by default.
    
    .PARAMETER UserNames
        Array of samAccountNames to analyze
    
    .PARAMETER DomainController
        Target domain controller to query
    
    .PARAMETER ExcludeDefaultGroups
        Exclude common default domain groups. Default is $true
    
    .PARAMETER MaxGroupSize
        Maximum group member count to process. Groups larger than this are skipped. Default is 5000
    
    .EXAMPLE
        Get-CommonADGroups -UserNames @("jdoe", "jsmith", "bwilliams") -DomainController "DC01.contoso.com"
    
    .EXAMPLE
        $users = @("user1", "user2", "user3")
        Get-CommonADGroups -UserNames $users -DomainController "DC01" -MaxGroupSize 10000
    #>
    
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string[]]$UserNames,
        [Parameter(Mandatory = $true)]
        [string]$DomainController,
        [Parameter(Mandatory = $false)]
        [bool]$ExcludeDefaultGroups = $true,
        [Parameter(Mandatory = $false)]
        [int]$MaxGroupSize = 5000
    )
    
    Begin {
        # Verify Active Directory module is available
        If (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Throw "Active Directory module is not available. Please install RSAT tools."
        }
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Default groups to exclude
        $excludedGroups = @(
            'Domain Users',
            'Domain Computers',
            'Authenticated Users',
            'Everyone',
            'Users'
        )
    }
    
    Process {
        Try {
            # Validate users exist and get their group memberships
            $userGroups = @{ }
            $validUsers = @()
            
            Write-Verbose "Retrieving group memberships for users..."
            
            ForEach ($userName In $UserNames) {
                Try {
                    $user = Get-ADUser -Identity $userName -Server $DomainController -Properties MemberOf -ErrorAction Stop
                    $validUsers += $userName
                    $userGroups[$userName] = $user.MemberOf | ForEach-Object {
                        (Get-ADGroup -Identity $_ -Server $DomainController).Name
                    }
                    Write-Verbose "Found $($userGroups[$userName].Count) groups for $userName"
                } Catch {
                    Write-Warning "Could not find user: $userName on $DomainController"
                }
            }
            
            If ($validUsers.Count -lt 2) {
                Write-Warning "Need at least 2 valid users to find common groups."
                Return
            }
            
            # Find common groups across all users
            Write-Verbose "Finding common groups..."
            $commonGroups = $userGroups[$validUsers[0]]
            
            For ($i = 1; $i -lt $validUsers.Count; $i++) {
                $commonGroups = $commonGroups | Where-Object { $userGroups[$validUsers[$i]] -contains $_ }
            }
            
            # Exclude default groups if requested
            If ($ExcludeDefaultGroups) {
                $beforeCount = $commonGroups.Count
                $commonGroups = $commonGroups | Where-Object { $_ -notin $excludedGroups }
                $excludedCount = $beforeCount - $commonGroups.Count
                If ($excludedCount -gt 0) {
                    Write-Verbose "Excluded $excludedCount default domain group(s)"
                }
            }
            
            If ($commonGroups.Count -eq 0) {
                Write-Host "No common groups found for the specified users." -ForegroundColor Yellow
                Return
            }
            
            Write-Host "`nFound $($commonGroups.Count) common group(s):" -ForegroundColor Green
            Write-Host ("=" * 80)
            
            # For each common group, list all members
            $results = @()
            
            ForEach ($groupName In $commonGroups) {
                Write-Host "`nGroup: $groupName" -ForegroundColor Cyan
                
                Try {
                    $group = Get-ADGroup -Filter "Name -eq '$groupName'" -Server $DomainController -Properties Members
                    $memberCount = ($group.Members | Measure-Object).Count
                    
                    # Check if group is too large
                    If ($memberCount -gt $MaxGroupSize) {
                        Write-Host "  ⚠ Skipping - Group has $memberCount members (exceeds limit of $MaxGroupSize)" -ForegroundColor Yellow
                        
                        $results += [PSCustomObject]@{
                            GroupName           = $groupName
                            TotalMembers        = $memberCount
                            TargetUsers         = $validUsers.Count
                            AdditionalMembers   = "N/A - Group too large"
                            AdditionalUsersList = "Group exceeds size limit"
                            Status              = "Skipped"
                        }
                        Continue
                    }
                    
                    # Get members using recursive call with error handling
                    $members = @()
                    Try {
                        $members = Get-ADGroupMember -Identity $group -Server $DomainController -ErrorAction Stop |
                        Where-Object { $_.objectClass -eq 'user' } |
                        Select-Object -ExpandProperty SamAccountName
                    } Catch {
                        If ($_.Exception.Message -like "*size limit*") {
                            Write-Host "  ⚠ Skipping - Group size limit exceeded" -ForegroundColor Yellow
                            
                            $results += [PSCustomObject]@{
                                GroupName           = $groupName
                                TotalMembers        = "Unknown (too large)"
                                TargetUsers         = $validUsers.Count
                                AdditionalMembers   = "N/A - Size limit exceeded"
                                AdditionalUsersList = "Group exceeds size limit"
                                Status              = "Skipped"
                            }
                            Continue
                        } Else {
                            Throw
                        }
                    }
                    
                    $extraMembers = $members | Where-Object { $_ -notin $validUsers }
                    
                    Write-Host "  Total members: $($members.Count)"
                    Write-Host "  Target users: $($validUsers.Count)"
                    Write-Host "  Additional members: $($extraMembers.Count)"
                    
                    If ($extraMembers.Count -gt 0) {
                        Write-Host "  Additional users:" -ForegroundColor Yellow
                        If ($extraMembers.Count -le 50) {
                            $extraMembers | ForEach-Object { Write-Host "    - $_" }
                        } Else {
                            $extraMembers | Select-Object -First 50 | ForEach-Object { Write-Host "    - $_" }
                            Write-Host "    ... and $($extraMembers.Count - 50) more" -ForegroundColor Gray
                        }
                    } Else {
                        Write-Host "  No additional members" -ForegroundColor Gray
                    }
                    
                    # Build result object
                    $results += [PSCustomObject]@{
                        GroupName           = $groupName
                        TotalMembers        = $members.Count
                        TargetUsers         = $validUsers.Count
                        AdditionalMembers   = $extraMembers.Count
                        AdditionalUsersList = $extraMembers -join ", "
                        Status              = "Processed"
                    }
                } Catch {
                    Write-Warning "Error processing group '$groupName': $($_.Exception.Message)"
                    
                    $results += [PSCustomObject]@{
                        GroupName           = $groupName
                        TotalMembers        = "Error"
                        TargetUsers         = $validUsers.Count
                        AdditionalMembers   = "Error"
                        AdditionalUsersList = "Error: $($_.Exception.Message)"
                        Status              = "Error"
                    }
                }
            }
            
            Write-Host "`n" ("=" * 80)
            Write-Host "Summary:" -ForegroundColor Green
            Write-Host "  Analyzed users: $($validUsers -join ', ')"
            Write-Host "  Common groups found: $($commonGroups.Count)"
            Write-Host "  Successfully processed: $(($results | Where-Object { $_.Status -eq 'Processed' }).Count)"
            Write-Host "  Skipped (too large): $(($results | Where-Object { $_.Status -eq 'Skipped' }).Count)"
            Write-Host "  Errors: $(($results | Where-Object { $_.Status -eq 'Error' }).Count)"
            
            # Return structured results
            Return $results
        } Catch {
            Write-Error "An error occurred: $_"
        }
    }
}

# Example usage (commented out):
# Get-CommonADGroups -UserNames @("jdoe", "jsmith") -DomainController "DC01.contoso.com" -Verbose
# Get-CommonADGroups -UserNames @("jdoe", "jsmith") -DomainController "DC01.contoso.com" -ExcludeDefaultGroups $false -MaxGroupSize 10000