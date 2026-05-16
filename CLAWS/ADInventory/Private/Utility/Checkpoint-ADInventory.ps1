function Save-ADInventoryCheckpoint {
    <#
    .SYNOPSIS
        Saves inventory collection checkpoint for resume capability

    .DESCRIPTION
        Saves the current state of an inventory collection to enable resuming
        if the process is interrupted. Checkpoint includes completed domains,
        statistics, and collection state.

        NEW FEATURE - Not in original script:
        - Resume capability for long-running inventories
        - Prevents data loss from interruptions
        - Allows incremental collection

    .PARAMETER InventoryID
        The inventory ID (GUID) for this collection

    .PARAMETER OutputPath
        Directory where checkpoint file will be saved

    .PARAMETER CompletedDomains
        Array of domain names that have been completed

    .PARAMETER Statistics
        Hashtable of collection statistics

    .PARAMETER Metadata
        Additional metadata to save (domains list, config, etc.)

    .OUTPUTS
        Path to checkpoint file

    .EXAMPLE
        $checkpointPath = Save-ADInventoryCheckpoint `
            -InventoryID $session.InventoryID `
            -OutputPath $outputPath `
            -CompletedDomains $completedDomains `
            -Statistics $session.Statistics `
            -Metadata @{
                TotalDomains = $session.Domains.Count
                StartTime = $session.StartTime
            }

    .NOTES
        Part of SSNC.ADInventory module

        Checkpoint File Format:
        - JSON file with .checkpoint extension
        - Stored in output directory
        - Named: {InventoryID}.checkpoint

        Security Considerations:
        - Checkpoint files may contain sensitive domain names
        - Store in secure location
        - Clean up after successful completion

        Performance:
        - Checkpoint saves are fast (< 100ms)
        - Save after each domain completes
        - Minimal overhead
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$InventoryID,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$CompletedDomains,

        [Parameter(Mandatory = $true)]
        [hashtable]$Statistics,

        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{}
    )

    process {
        try {
            Write-ADInventoryLog -Level Debug -Message "Saving inventory checkpoint" `
                -Context @{
                    InventoryID = $InventoryID.ToString()
                    CompletedDomains = $CompletedDomains.Count
                }

            # Build checkpoint object
            $checkpoint = @{
                InventoryID = $InventoryID.ToString()
                CheckpointVersion = "1.0"
                SavedAt = (Get-Date).ToString('o')  # ISO 8601 format
                CompletedDomains = $CompletedDomains
                Statistics = $Statistics
                Metadata = $Metadata
            }

            # Convert to JSON
            $json = $checkpoint | ConvertTo-Json -Depth 10 -Compress

            # Build checkpoint file path
            $checkpointFileName = "$($InventoryID.ToString()).checkpoint"
            $checkpointPath = Join-Path $OutputPath $checkpointFileName

            # Save to file (atomic write using temp file + move)
            $tempPath = "$checkpointPath.tmp"

            try {
                # Write to temp file
                [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)

                # Move to final location (atomic on same filesystem)
                if (Test-Path $checkpointPath) {
                    Remove-Item $checkpointPath -Force
                }
                Move-Item $tempPath $checkpointPath -Force

                Write-ADInventoryLog -Level Info -Message "Checkpoint saved successfully" `
                    -Context @{
                        InventoryID = $InventoryID.ToString()
                        CheckpointPath = $checkpointPath
                        CompletedDomains = $CompletedDomains.Count
                    }

                return $checkpointPath
            }
            finally {
                # Cleanup temp file if it still exists
                if (Test-Path $tempPath) {
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to save checkpoint" `
                -Context @{ InventoryID = $InventoryID.ToString() } `
                -Exception $_.Exception

            # Don't throw - checkpoint save failure shouldn't stop collection
            return $null
        }
    }
}

function Get-ADInventoryCheckpoint {
    <#
    .SYNOPSIS
        Loads a previously saved inventory checkpoint

    .DESCRIPTION
        Loads checkpoint data for a previous inventory collection to enable resuming.
        Returns checkpoint information including completed domains and statistics.

    .PARAMETER InventoryID
        The inventory ID (GUID) to load checkpoint for

    .PARAMETER OutputPath
        Directory where checkpoint file is located

    .PARAMETER CheckpointPath
        Direct path to checkpoint file (alternative to InventoryID + OutputPath)

    .OUTPUTS
        PSCustomObject with checkpoint data, or $null if not found

    .EXAMPLE
        $checkpoint = Get-ADInventoryCheckpoint `
            -InventoryID $inventoryId `
            -OutputPath $outputPath

        if ($checkpoint) {
            $remainingDomains = $allDomains | Where-Object { $_ -notin $checkpoint.CompletedDomains }
        }

    .EXAMPLE
        # Load by path
        $checkpoint = Get-ADInventoryCheckpoint -CheckpointPath "C:\path\to\checkpoint.file"

    .NOTES
        Part of SSNC.ADInventory module
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInventoryID')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByInventoryID', Mandatory = $true)]
        [guid]$InventoryID,

        [Parameter(ParameterSetName = 'ByInventoryID', Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputPath,

        [Parameter(ParameterSetName = 'ByPath', Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CheckpointPath
    )

    process {
        try {
            # Determine checkpoint path (use separate variable to avoid validation re-trigger)
            $resolvedCheckpointPath = if ($PSCmdlet.ParameterSetName -eq 'ByInventoryID') {
                $checkpointFileName = "$($InventoryID.ToString()).checkpoint"
                Join-Path $OutputPath $checkpointFileName
            }
            else {
                $CheckpointPath
            }

            # Check if checkpoint exists
            if (-not (Test-Path $resolvedCheckpointPath -PathType Leaf)) {
                Write-ADInventoryLog -Level Debug -Message "Checkpoint file not found" `
                    -Context @{ CheckpointPath = $resolvedCheckpointPath }
                return $null
            }

            Write-ADInventoryLog -Level Debug -Message "Loading checkpoint" `
                -Context @{ CheckpointPath = $resolvedCheckpointPath }

            # Read and parse checkpoint file
            $json = [System.IO.File]::ReadAllText($resolvedCheckpointPath, [System.Text.Encoding]::UTF8)
            $checkpoint = $json | ConvertFrom-Json

            # Validate checkpoint version
            if ($checkpoint.CheckpointVersion -ne "1.0") {
                Write-ADInventoryLog -Level Warning -Message "Checkpoint version mismatch" `
                    -Context @{
                        ExpectedVersion = "1.0"
                        ActualVersion = $checkpoint.CheckpointVersion
                    }
                # Continue anyway - best effort
            }

            Write-ADInventoryLog -Level Info -Message "Checkpoint loaded successfully" `
                -Context @{
                    InventoryID = $checkpoint.InventoryID
                    SavedAt = $checkpoint.SavedAt
                    CompletedDomains = $checkpoint.CompletedDomains.Count
                }

            # Convert back to proper types
            $checkpointObj = [PSCustomObject]@{
                InventoryID = [guid]::Parse($checkpoint.InventoryID)
                CheckpointVersion = $checkpoint.CheckpointVersion
                SavedAt = [datetime]::Parse($checkpoint.SavedAt)
                CompletedDomains = @($checkpoint.CompletedDomains)
                Statistics = @{}
                Metadata = @{}
            }

            # Convert statistics hashtable
            foreach ($key in $checkpoint.Statistics.PSObject.Properties.Name) {
                $checkpointObj.Statistics[$key] = $checkpoint.Statistics.$key
            }

            # Convert metadata hashtable
            if ($checkpoint.Metadata) {
                foreach ($key in $checkpoint.Metadata.PSObject.Properties.Name) {
                    $checkpointObj.Metadata[$key] = $checkpoint.Metadata.$key
                }
            }

            return $checkpointObj
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Failed to load checkpoint" `
                -Context @{ CheckpointPath = $resolvedCheckpointPath } `
                -Exception $_.Exception

            return $null
        }
    }
}

function Remove-ADInventoryCheckpoint {
    <#
    .SYNOPSIS
        Removes a checkpoint file after successful completion

    .DESCRIPTION
        Cleans up checkpoint files after inventory collection completes successfully.
        Should be called in finally block or after successful collection.

    .PARAMETER InventoryID
        The inventory ID (GUID) to remove checkpoint for

    .PARAMETER OutputPath
        Directory where checkpoint file is located

    .PARAMETER CheckpointPath
        Direct path to checkpoint file

    .EXAMPLE
        Remove-ADInventoryCheckpoint -InventoryID $inventoryId -OutputPath $outputPath

    .EXAMPLE
        # Remove by path
        Remove-ADInventoryCheckpoint -CheckpointPath $checkpointPath

    .NOTES
        Part of SSNC.ADInventory module
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInventoryID')]
    param(
        [Parameter(ParameterSetName = 'ByInventoryID', Mandatory = $true)]
        [guid]$InventoryID,

        [Parameter(ParameterSetName = 'ByInventoryID', Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputPath,

        [Parameter(ParameterSetName = 'ByPath', Mandatory = $true)]
        [string]$CheckpointPath
    )

    process {
        try {
            # Determine checkpoint path (use separate variable to avoid validation re-trigger)
            $resolvedCheckpointPath = if ($PSCmdlet.ParameterSetName -eq 'ByInventoryID') {
                $checkpointFileName = "$($InventoryID.ToString()).checkpoint"
                Join-Path $OutputPath $checkpointFileName
            }
            else {
                $CheckpointPath
            }

            # Check if checkpoint exists
            if (Test-Path $resolvedCheckpointPath -PathType Leaf) {
                Remove-Item $resolvedCheckpointPath -Force

                Write-ADInventoryLog -Level Debug -Message "Checkpoint removed" `
                    -Context @{ CheckpointPath = $resolvedCheckpointPath }
            }
            else {
                Write-ADInventoryLog -Level Debug -Message "Checkpoint file not found (already removed?)" `
                    -Context @{ CheckpointPath = $resolvedCheckpointPath }
            }
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to remove checkpoint" `
                -Context @{ CheckpointPath = $resolvedCheckpointPath } `
                -Exception $_.Exception

            # Don't throw - cleanup failure is not critical
        }
    }
}

function Test-ADInventoryCheckpoint {
    <#
    .SYNOPSIS
        Tests if a checkpoint exists for an inventory

    .DESCRIPTION
        Quick check to determine if a checkpoint file exists for resuming.

    .PARAMETER InventoryID
        The inventory ID (GUID) to check

    .PARAMETER OutputPath
        Directory where checkpoint file would be located

    .OUTPUTS
        Boolean - $true if checkpoint exists, $false otherwise

    .EXAMPLE
        if (Test-ADInventoryCheckpoint -InventoryID $id -OutputPath $path) {
            Write-Host "Resumable checkpoint found"
        }

    .NOTES
        Part of SSNC.ADInventory module
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$InventoryID,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputPath
    )

    process {
        $checkpointFileName = "$($InventoryID.ToString()).checkpoint"
        $checkpointPath = Join-Path $OutputPath $checkpointFileName

        return (Test-Path $checkpointPath -PathType Leaf)
    }
}
