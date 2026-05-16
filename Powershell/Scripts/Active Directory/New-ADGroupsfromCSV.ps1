Function Create-Group($group) {
    $groupParams = @{
        Name        = $group.Name
        Description = $group.Description
        GroupScope  = $group.GroupScope
        Path        = $group.OU
        Server      = $closestDC
        ErrorAction = 'SilentlyContinue'
    }
    
    # Creating the AD Group
    $newGroup = New-ADGroup @groupParams
    
    If ($newGroup) {
        Write-Host "Group $($group.Name) created successfully on $closestDC."
        
        # Adding the group to another group if specified
        If ($group.MemberOf) {
            $memberOfParams = @{
                Identity = $group.MemberOf
                Members  = $group.Name
                Server   = $closestDC
            }
            Add-ADGroupMember @memberOfParams
            Write-Host "Group $($group.Name) added to $($group.MemberOf)."
        }
    } Else {
        Write-Host "Failed to create group $($group.Name) on $closestDC."
    }
}

Function Check-ADGroupExists {
    Param (
        [string]$GroupName
    )
    
    # Attempt to retrieve the AD group by name
    Try {
        $group = Get-ADGroup -Identity $GroupName -ErrorAction Stop
        If ($group) {
            #Write-Host "Group '$GroupName' exists."
            Return $true
        }
    } Catch {
        #Write-Host "Group '$GroupName' does not exist."
        Return $false
    }
}

Function Create-ADGroupsFromCSV {
    Param (
        [string]$CSVFileName
    )
    
    # Importing the CSV file
    $groups = Import-Csv -Path $CsvFileName
    
    # Find the nearest domain controller to ensure we have access to all the groups we create with out waiting for replication
    $closestDC = (Get-ADDomainController -Discover -NextClosestSite).HostName | Select-Object -First 1
        
    # Create Domain Local groups first
    $domainLocalGroups = $groups | Where-Object { $_.GroupScope -eq 'DomainLocal' }
    $otherGroups = $groups | Where-Object { $_.GroupScope -ne 'DomainLocal' }
    
    #create the DLGs first so that the GGs can use them
    ForEach ($group In $domainLocalGroups) {
        If (!(Check-ADGroupExists -GroupName $group.Name)) {
            Create-Group $group
        }        
    }
    
    #GGs are a MemberOf DLG, we will create them second 
    ForEach ($group In $otherGroups) {
        If (!(Check-ADGroupExists -GroupName $group.Name)) {
            Create-Group $group
        }
    }
}
