function Set-CloudFileShare {
    <#
    .SYNOPSIS
        Updates a file share.
    
    .DESCRIPTION
        Updates the configuration of a specified file share.
        Currently supports updating the size of the file share.
    
    .PARAMETER Id
        The unique identifier of the file share to update. Required.
    
    .PARAMETER SizeGB
        The new size of the file share in GB. Required.
    
    .EXAMPLE
        PS> Set-CloudFileShare -Id "fs-..." -SizeGB 200
        
        Resizes the file share to 200GB.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('FileShareId')]
        [string]$Id,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [int]$SizeGB
    )
    
    try {
        $body = @{
            sizeGB = $SizeGB
        }
        
        if (-not $PSCmdlet.ShouldProcess("file share '$Id' to $SizeGB GB", 'Resize')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "storage/file-shares/$Id" -Method 'PUT' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to update file share: $($_.Exception.Message)"
        return $null
    }
}
