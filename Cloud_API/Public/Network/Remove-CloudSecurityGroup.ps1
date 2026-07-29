function Remove-CloudSecurityGroup {
    <#
    .SYNOPSIS
        Removes a security group.
    
    .DESCRIPTION
        Deletes a specified security group.
    
    .PARAMETER Id
        The unique identifier of the security group. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Remove-CloudSecurityGroup -Id "securitygroup-..."
        
        Prompts for confirmation before removing the security group.
    
    .EXAMPLE
        PS> Remove-CloudSecurityGroup -Id "securitygroup-..." -Force
        
        Removes the security group without prompting.
    
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
        [Alias('SecuritygroupId', 'ResourceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    begin {
        $headers = $null
        try {
            $headers = New-CloudAPIHeaders
        }
        catch {
            Write-Error -Message "Failed to initialize API headers: $($_.Exception.Message)" -ErrorId 'InitializeCloudAPIHeadersFailed'
            return
        }
        $results = @()
    }
    
    process {
        try {
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("security group '$Id'", 'Remove')) {
                return $null
            }
            
            $response = Invoke-CloudAPIRequest -Path "network/securitygroups/$Id" -Method 'DELETE' -Headers $headers
            
            $results += $response
        }
        catch {
            Write-Error -Message "Failed to remove security group '$Id': $($_.Exception.Message)" -ErrorId 'RemoveCloudSecurityGroupFailed'
        }
    }
    
    end {
        return $results
    }
}
