function Copy-CloudInstance {
    <#
    .SYNOPSIS
        Creates a clone of an existing cloud instance.
    
    .DESCRIPTION
        Creates an exact copy (clone) of a cloud instance, including its configuration,
        attached volumes, and network settings. The source instance can be running or stopped.
    
    .PARAMETER SourceInstanceId
        The unique identifier of the instance to clone. This parameter is mandatory.
        Accepts pipeline input.
    
    .PARAMETER Name
        The name for the new cloned instance.
    
    .PARAMETER SubprojectId
        The sub-project ID where the cloned instance will be created.
    
    .PARAMETER Site
        The deployment zone/site for the cloned instance.
    
    .PARAMETER Wait
        If specified, waits for the clone operation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the clone operation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> Copy-CloudInstance -SourceInstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Clone-Instance-01"
        
        Creates a clone of the specified instance.
    
    .EXAMPLE
        PS> Copy-CloudInstance -SourceInstanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "Clone-Instance-01" -SubprojectId "subproject-..." -Wait
        
        Creates a clone in a different sub-project and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId', 'Id')]
        [string]$SourceInstanceId,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [string]$Site,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate source instance exists
            $sourceInstance = Get-CloudInstance -Id $SourceInstanceId
            if (-not $sourceInstance) {
                Write-Error "Source instance '$SourceInstanceId' not found"
                return $null
            }
            
            # Build request body
            $body = @{}
            if ($Name) { $body['name'] = $Name }
            if ($SubprojectId) { $body['subprojectId'] = $SubprojectId }
            if ($Site) { $body['site'] = $Site }
            
            # Copy configuration from source if not specified
            if (-not $Name) { $body['name'] = "$($sourceInstance.name)-clone" }
            if (-not $SubprojectId) { $body['subprojectId'] = $sourceInstance.subprojectId }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$SourceInstanceId/clone"
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
            Write-Error "Failed to clone instance: $($_.Exception.Message)"
            return $null
        }
    }
}
