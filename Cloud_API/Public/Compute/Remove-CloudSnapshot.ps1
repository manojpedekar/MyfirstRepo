function Remove-CloudSnapshot {
    <#
    .SYNOPSIS
        Removes a cloud snapshot.
    
    .DESCRIPTION
        Deletes a snapshot from the cloud. This operation is permanent and cannot
        be undone. Supports ShouldProcess for safety.
    
    .PARAMETER Id
        The unique identifier of the snapshot to remove. This parameter is mandatory.
    
    .PARAMETER Force
        If specified, suppresses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Remove-CloudSnapshot -Id "snap-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Removes the specified snapshot after confirmation.
    
    .EXAMPLE
        PS> Remove-CloudSnapshot -Id "snap-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Removes the snapshot without confirmation.
    
    .EXAMPLE
        PS> Remove-CloudSnapshot -Id "snap-55c319eb-5944-4d00-a927-02e2eff4430a" -WhatIf
        
        Shows what would happen without actually removing the snapshot.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('SnapshotId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders
            
            # Get snapshot info for confirmation message
            $snapshot = Get-CloudSnapshot -Id $Id
            if (-not $snapshot) {
                Write-Error "Snapshot '$Id' not found"
                return $null
            }
            
            # Build confirmation message
            $target = "Snapshot: $($snapshot.name) ($Id)"
            $action = "Remove"
            
            if ($Force -or $PSCmdlet.ShouldProcess($target, $action)) {
                # Make API request
                $response = Invoke-CloudAPIRequest -Path "compute/snapshots/$Id" -Method 'DELETE' -Headers $headers
                
                Write-Verbose "Successfully removed snapshot $Id"
                return $response
            }
        }
        catch {
            Write-Error "Failed to remove snapshot: $($_.Exception.Message)"
            return $null
        }
    }
}
