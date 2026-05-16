function Expand-ADGroupMembership {
    <#
    .SYNOPSIS
        Computes flattened/recursive group memberships from direct memberships

    .DESCRIPTION
        Takes the direct group memberships from AD_GroupMembership and expands
        them recursively to show all effective memberships at all nesting levels.

        For example, if:
        - User Alice is in Group TeamDev
        - Group TeamDev is in Group AllEngineers
        - Group AllEngineers is in Group DomainUsers

        This function will produce:
        - Alice -> TeamDev (level 0)
        - Alice -> AllEngineers (level 1, via TeamDev)
        - Alice -> DomainUsers (level 2, via TeamDev -> AllEngineers)

    .PARAMETER Connection
        Open SQLite connection to the inventory database

    .PARAMETER InventoryID
        The inventory ID to process

    .OUTPUTS
        Array of PSCustomObject with flattened membership records

    .NOTES
        Part of SSNC.ADInventory module
        Handles circular group references by tracking visited groups
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SQLite.SQLiteConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [string]$InventoryID
    )

    Write-ADInventoryLog -Level Info -Message "Starting group membership flattening" `
        -Context @{ InventoryID = $InventoryID }

    try {
        # Load all objects into a hashtable for quick lookup (SID -> ObjectType)
        $objectTypes = @{}
        $objectQuery = "SELECT SID_String, ObjectType FROM AD_Object WHERE InventoryID = @InventoryID"
        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $objectQuery
        $param = $cmd.CreateParameter()
        $param.ParameterName = "@InventoryID"
        $param.Value = $InventoryID
        [void]$cmd.Parameters.Add($param)

        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $objectTypes[$reader["SID_String"]] = [int]$reader["ObjectType"]
        }
        $reader.Close()
        $cmd.Dispose()

        Write-ADInventoryLog -Level Debug -Message "Loaded object types" `
            -Context @{ ObjectCount = $objectTypes.Count }

        # Load all direct memberships into a hashtable (GroupSID -> array of MemberSIDs)
        $directMemberships = @{}
        $memberQuery = "SELECT GroupSID, MemberSID FROM AD_GroupMembership WHERE InventoryID = @InventoryID"
        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $memberQuery
        $param = $cmd.CreateParameter()
        $param.ParameterName = "@InventoryID"
        $param.Value = $InventoryID
        [void]$cmd.Parameters.Add($param)

        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $groupSID = $reader["GroupSID"].ToString()
            $memberSID = $reader["MemberSID"].ToString()
            if (-not $directMemberships.ContainsKey($groupSID)) {
                $directMemberships[$groupSID] = [System.Collections.ArrayList]::new()
            }
            [void]$directMemberships[$groupSID].Add($memberSID)
        }
        $reader.Close()
        $cmd.Dispose()

        Write-ADInventoryLog -Level Debug -Message "Loaded direct memberships" `
            -Context @{ GroupCount = $directMemberships.Count }

        # Get all groups (ObjectType = 2)
        $allGroups = $objectTypes.GetEnumerator() | Where-Object { $_.Value -eq 2 } | ForEach-Object { $_.Key }

        Write-ADInventoryLog -Level Info -Message "Processing groups for flattening" `
            -Context @{ GroupCount = @($allGroups).Count }

        # Result collection
        $flatMemberships = [System.Collections.ArrayList]::new()
        $computedDate = (Get-Date).ToString('o')
        $processedCount = 0

        # Process each group
        foreach ($groupSID in $allGroups) {
            # Skip groups with no members
            if (-not $directMemberships.ContainsKey($groupSID)) {
                continue
            }

            # Track visited groups to prevent infinite loops (circular references)
            $visited = [System.Collections.Generic.HashSet[string]]::new()

            # Recursive function to expand members
            $expandMembers = {
                param($currentGroupSID, $level, $pathArray)

                # Prevent infinite loops
                if ($visited.Contains($currentGroupSID)) {
                    return
                }
                [void]$visited.Add($currentGroupSID)

                # Get direct members of current group
                if (-not $directMemberships.ContainsKey($currentGroupSID)) {
                    return
                }

                foreach ($memberSID in $directMemberships[$currentGroupSID]) {
                    # Get member type (default to 0 if unknown - could be FSP)
                    $memberType = if ($objectTypes.ContainsKey($memberSID)) { $objectTypes[$memberSID] } else { 0 }

                    # Build path for this member
                    $memberPath = $pathArray + @($memberSID)

                    # Create flattened record
                    $record = [PSCustomObject]@{
                        GroupSID     = $groupSID  # Original top-level group
                        MemberSID    = $memberSID
                        MemberType   = $memberType
                        NestingLevel = $level
                        PathToMember = ($memberPath | ConvertTo-Json -Compress)
                        InventoryID  = $InventoryID
                        ComputedDate = $computedDate
                    }
                    [void]$flatMemberships.Add($record)

                    # If member is a group, recurse into it
                    if ($memberType -eq 2) {
                        & $expandMembers $memberSID ($level + 1) $memberPath
                    }
                }
            }

            # Start expansion from this group
            & $expandMembers $groupSID 0 @($groupSID)

            $processedCount++
            if ($processedCount % 1000 -eq 0) {
                Write-ADInventoryLog -Level Debug -Message "Flattening progress" `
                    -Context @{ ProcessedGroups = $processedCount; FlatRecords = $flatMemberships.Count }
            }
        }

        Write-ADInventoryLog -Level Info -Message "Group membership flattening completed" `
            -Context @{
                GroupsProcessed = $processedCount
                FlatMemberships = $flatMemberships.Count
            }

        return $flatMemberships.ToArray()
    }
    catch {
        Write-ADInventoryLog -Level Error -Message "Failed to flatten group memberships" `
            -Exception $_.Exception
        throw
    }
}
