function Export-CloudInstance {
    <#
    .SYNOPSIS
        Exports an instance configuration as a template.
    
    .DESCRIPTION
        Exports the configuration of a cloud instance to create a reusable template.
        The exported configuration can be used to create new instances with the same
        settings (excluding instance-specific data like IP addresses).
    
    .PARAMETER Id
        The unique identifier of the instance to export. This parameter is mandatory.
    
    .PARAMETER Name
        A name for the exported template.
    
    .PARAMETER Description
        A description of the exported template.
    
    .PARAMETER Wait
        If specified, waits for the export operation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the export operation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> Export-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "WebServer-Template"
        
        Exports the instance configuration as a template.
    
    .EXAMPLE
        PS> Export-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "WebServer-Template" -Description "Template for web servers" -Wait
        
        Exports with description and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$Description,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate instance exists
            $instance = Get-CloudInstance -Id $Id
            if (-not $instance) {
                Write-Error "Instance '$Id' not found"
                return $null
            }
            
            # Build request body
            $body = @{}
            if ($Name) { $body['name'] = $Name }
            if ($Description) { $body['description'] = $Description }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$Id/export"
                Method = 'POST'
                Headers = $headers
                Body = $body
            }
            
            if ($Wait) { $invokeParams['Wait'] = $true }
            if ($Async) { $invokeParams['Async'] = $true }
            
            # Make API request
            $response = Invoke-CloudAPIRequest @invokeParams
            
            return $response
        }
        catch {
            Write-Error "Failed to export instance: $($_.Exception.Message)"
            return $null
        }
    }
}
