function Remove-CloudInstance {
    <#
    .SYNOPSIS
        Removes a cloud instance.
    
    .DESCRIPTION
        Deletes a specified cloud instance. By default, prompts for confirmation
        unless the -Force switch is used.
    
    .PARAMETER Id
        The unique identifier of the instance to remove. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Remove-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before removing the instance.
    
    .EXAMPLE
        PS> Remove-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Removes the instance without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId', 'ResourceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            # Get instance details for the confirmation message
            $instance = Get-CloudInstance -Id $Id
            $instanceName = if ($instance) { $instance.name } else { $Id }
            
            # Use ShouldProcess for confirmation
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("instance '$instanceName' ($Id)", 'Remove')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id" -Method 'DELETE' -Headers $headers
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to remove instance '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudInstanceFailed'
        }
    }
    
    end {
        return $results
    }
}
