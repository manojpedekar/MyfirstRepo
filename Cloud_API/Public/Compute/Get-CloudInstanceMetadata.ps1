function Get-CloudInstanceMetadata {
    <#
    .SYNOPSIS
        Retrieves metadata for a cloud instance.
    
    .DESCRIPTION
        Gets metadata information for a specified cloud instance, including details
        like last patch date, DNS aliases, and other instance-specific metadata.
    
    .PARAMETER Id
        The unique identifier of the instance. Required.
    
    .EXAMPLE
        PS> Get-CloudInstanceMetadata -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves metadata for the specified instance.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId')]
        [string]$Id
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id/meta" -Method 'GET' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve instance metadata: $($_.Exception.Message)"
        return $null
    }
}
