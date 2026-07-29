function Get-CloudFileShare {
    <#
    .SYNOPSIS
        Retrieves file share information.
    
    .DESCRIPTION
        Gets information about file shares. Can retrieve a specific file share by ID,
        or list all file shares in a sub-project.
    
    .PARAMETER Id
        The unique identifier of the file share.
    
    .PARAMETER SubprojectId
        The sub-project ID to list file shares from.
    
    .EXAMPLE
        PS> Get-CloudFileShare -Id "fs-00000000-0000-0000-0000-0000000000000"
        
        Retrieves details for a specific file share.
    
    .EXAMPLE
        PS> Get-CloudFileShare -SubprojectId "subproject-..."
        
        Lists all file shares in the specified sub-project.
    
    .EXAMPLE
        PS> Get-CloudFileShare
        
        Lists all file shares available.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [Alias('FileShareId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType
        
        if ($Id) {
            $path = "storage/file-shares/$Id"
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
        } else {
            $queryParams = @{
                sort = 'name%2Casc'
            }
            if ($SubprojectId) { $queryParams['subprojectId'] = $SubprojectId }
            
            $response = Invoke-CloudAPIRequest -Path 'storage/file-shares' -Method 'GET' -Headers $headers -QueryParameters $queryParams
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to retrieve file share(s): $($_.Exception.Message)"
        return $null
    }
}
