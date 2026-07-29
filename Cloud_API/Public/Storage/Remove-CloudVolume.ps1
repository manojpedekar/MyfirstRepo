function Remove-CloudVolume {
    <#
    .SYNOPSIS
        Removes a cloud volume.
    
    .DESCRIPTION
        Deletes a specified cloud volume.
    
    .PARAMETER Id
        The unique identifier of the volume. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudVolume -Id "v-00000000-0000-0000-0000-0000000000000"
        
        Prompts for confirmation before removing the volume.
    
    .EXAMPLE
        PS> Remove-CloudVolume -Id "v-..." -Force
        
        Removes the volume without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('VolumeId', 'ResourceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("volume '$Id'", 'Remove')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "storage/volumes/$Id" -Method 'DELETE' -Headers $headers
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to remove volume '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudVolumeFailed'
        }
    }
    
    end {
        return $results
    }
}
