function Get-ADObjectBatch {
    <#
    .SYNOPSIS
        Retrieves AD objects with proper resource management and progress reporting

    .DESCRIPTION
        Executes an LDAP query and retrieves AD objects with proper disposal of resources.
        This function fixes the connection leaks present in the original Get-ADObjects function
        by using try/finally blocks to ensure SearchResultCollection is always disposed.

        Supports progress reporting and optional per-object processing via script block.

    .PARAMETER DirectoryEntry
        The DirectoryEntry object to search from

    .PARAMETER Filter
        LDAP filter string (e.g., "(&(objectCategory=person)(objectClass=user))")

    .PARAMETER PropertiesToLoad
        Array of AD property names to retrieve

    .PARAMETER PageSize
        Page size for paged searches (default: 1000)

    .PARAMETER SearchScope
        Search scope: Base, OneLevel, or Subtree (default: Subtree)

    .PARAMETER ServerTimeoutMinutes
        Server-side query timeout in minutes (default: 10)

    .PARAMETER ClientTimeoutMinutes
        Client-side query timeout in minutes (default: 15)

    .PARAMETER ReferralChasing
        Referral chasing behavior: None, Subordinate, All (default: None)

    .PARAMETER ProcessObject
        Optional script block to process each SearchResult
        If not provided, returns raw SearchResult objects
        Script block receives SearchResult as $_ or $args[0]

    .PARAMETER ProgressActivity
        Activity name for Write-Progress (default: "Retrieving AD Objects")

    .PARAMETER ShowProgress
        Show progress bar during retrieval (default: $true)

    .OUTPUTS
        SearchResult objects or processed objects (if ProcessObject specified)

    .EXAMPLE
        $de = New-ADConnection -Server "DC01" -Domain "contoso.com"
        try {
            $users = Get-ADObjectBatch -DirectoryEntry $de `
                -Filter "(&(objectCategory=person)(objectClass=user))" `
                -PropertiesToLoad @('samAccountName', 'mail', 'objectSid') `
                -ProcessObject {
                    param($result)
                    [PSCustomObject]@{
                        SamAccountName = $result.Properties['samaccountname'][0]
                        Email = $result.Properties['mail'][0]
                    }
                }
        } finally {
            $de.Dispose()
        }

    .EXAMPLE
        # Retrieve FSPs without referral chasing
        $fsps = Get-ADObjectBatch -DirectoryEntry $de `
            -Filter "(objectClass=foreignSecurityPrincipal)" `
            -PropertiesToLoad @('objectSid', 'distinguishedName') `
            -ReferralChasing None `
            -SearchScope OneLevel

    .NOTES
        Part of SSNC.ADInventory module

        CRITICAL FIX: Resource Management
        This function fixes the connection leak in the original Get-ADObjects:
        - Original: $src.Dispose() only called on success path (line 512)
        - Fixed: try/finally ensures disposal even if exception occurs
        - Also properly disposes DirectorySearcher

        Improvements:
        - Proper try/finally for resource cleanup
        - Progress reporting with percentage
        - Optional per-object processing
        - Configurable timeouts
        - Better error context
    #>
    [CmdletBinding()]
    [OutputType([System.DirectoryServices.SearchResult[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$PropertiesToLoad,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 5000)]
        [int]$PageSize = 1000,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Base', 'OneLevel', 'Subtree')]
        [string]$SearchScope = 'Subtree',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$ServerTimeoutMinutes = 10,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$ClientTimeoutMinutes = 15,

        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'Subordinate', 'All')]
        [string]$ReferralChasing = 'None',

        [Parameter(Mandatory = $false)]
        [scriptblock]$ProcessObject,

        [Parameter(Mandatory = $false)]
        [string]$ProgressActivity = "Retrieving AD Objects",

        [Parameter(Mandatory = $false)]
        [bool]$ShowProgress = $true
    )

    process {
        $ds = $null
        $results = $null
        $processedObjects = [System.Collections.ArrayList]::new()
        $processedCount = 0

        try {
            # Create directory searcher with proper configuration
            $ds = New-DirectorySearcher -DirectoryEntry $DirectoryEntry `
                -Filter $Filter `
                -PropertiesToLoad $PropertiesToLoad `
                -PageSize $PageSize `
                -SearchScope $SearchScope `
                -ServerTimeoutMinutes $ServerTimeoutMinutes `
                -ClientTimeoutMinutes $ClientTimeoutMinutes `
                -ReferralChasing $ReferralChasing

            Write-ADInventoryLog -Level Info -Message "Executing LDAP query" `
                -Context @{
                    Filter = $Filter
                    Properties = ($PropertiesToLoad -join ', ')
                }

            # Execute search
            $results = $ds.FindAll()
            $total = $results.Count

            Write-ADInventoryLog -Level Info -Message "Query returned results" `
                -Context @{
                    Count = $total
                    Filter = $Filter
                }

            # Generate unique progress ID
            $progressId = Get-Random -Minimum 1000 -Maximum 9999

            # Process each result
            foreach ($result in $results) {
                $processedCount++

                # Update progress
                if ($ShowProgress -and (($processedCount % 100) -eq 0 -or $processedCount -eq $total)) {
                    $percentComplete = if ($total -gt 0) {
                        [int](($processedCount / $total) * 100)
                    } else {
                        0
                    }

                    Write-Progress -Id $progressId `
                        -Activity $ProgressActivity `
                        -Status "$processedCount of $total objects processed" `
                        -PercentComplete $percentComplete
                }

                # Process object with script block if provided
                if ($ProcessObject) {
                    try {
                        $processedObj = & $ProcessObject $result
                        if ($null -ne $processedObj) {
                            [void]$processedObjects.Add($processedObj)
                        }
                    }
                    catch {
                        Write-ADInventoryLog -Level Warning -Message "Error processing object" `
                            -Context @{
                                DN = $result.Properties['distinguishedname'][0]
                            } `
                            -Exception $_.Exception
                    }
                }
                else {
                    # Return raw SearchResult
                    [void]$processedObjects.Add($result)
                }
            }

            # Clear progress
            if ($ShowProgress) {
                Write-Progress -Id $progressId -Activity $ProgressActivity -Completed
            }

            Write-ADInventoryLog -Level Info -Message "Batch retrieval completed" `
                -Context @{
                    Retrieved = $total
                    Processed = $processedObjects.Count
                    Filter = $Filter
                }

            return $processedObjects.ToArray()
        }
        catch [System.DirectoryServices.DirectoryServicesCOMException] {
            Write-ADInventoryLog -Level Error -Message "LDAP query failed with COM exception" `
                -Context @{
                    Filter = $Filter
                    ErrorCode = $_.Exception.ErrorCode
                } `
                -Exception $_.Exception

            throw "LDAP query failed: $_"
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to retrieve AD objects" `
                -Context @{
                    Filter = $Filter
                } `
                -Exception $_.Exception

            throw "Failed to retrieve AD objects: $_"
        }
        finally {
            # CRITICAL: Ensure resources are disposed even if exception occurs
            # This fixes the connection leak from the original script

            if ($results) {
                try {
                    Write-ADInventoryLog -Level Debug -Message "Disposing SearchResultCollection"
                    $results.Dispose()
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Error disposing SearchResultCollection" `
                        -Exception $_.Exception
                }
            }

            if ($ds) {
                try {
                    Write-ADInventoryLog -Level Debug -Message "Disposing DirectorySearcher"
                    $ds.Dispose()
                }
                catch {
                    Write-ADInventoryLog -Level Warning -Message "Error disposing DirectorySearcher" `
                        -Exception $_.Exception
                }
            }
        }
    }
}
