function Reset-CloudInstance {
    <#
    .SYNOPSIS
        Hard resets a cloud instance.
    
    .DESCRIPTION
        Performs a hard reset (power cycle) of a cloud instance.
        This is equivalent to pressing the reset button on a physical machine.
        WARNING: This is not a graceful shutdown and may result in data loss.
    
    .PARAMETER Id
        The unique identifier of the instance to reset. Required.
    
    .PARAMETER ForceConfirm
        If specified, bypasses the confirmation prompt.
    
    .EXAMPLE
        PS> Reset-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation then hard resets the instance.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
        Warning: This is a hard reset and may cause data loss.
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^[a-z]+-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$ForceConfirm
    )
    
    try {
        $instance = Get-CloudInstance -Id $Id
        $instanceName = if ($instance) { $instance.name } else { $Id }
        
        if (-not $ForceConfirm) {
            Write-Warning "This will HARD RESET instance '$instanceName' ($Id). This may cause data loss!"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Hard reset the instance (may cause data loss)"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel the operation"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $result = $host.UI.PromptForChoice("Confirm Hard Reset", "Are you sure you want to continue?", $options, 1)
            
            if ($result -ne 0) {
                Write-Verbose "Operation cancelled by user"
                Write-Warning "Hard reset operation cancelled."
                return $null
            }
        }
        
        if (-not $PSCmdlet.ShouldProcess("instance '$instanceName' ($Id)", 'Hard Reset')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id/power?action=RESET" -Method 'PUT' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error -Message "Failed to reset instance: $($_.Exception.Message)" -ErrorId 'ResetCloudInstanceFailed'
        return $null
    }
}
