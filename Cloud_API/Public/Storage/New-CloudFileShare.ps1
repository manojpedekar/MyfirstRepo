function New-CloudFileShare {
    <#
    .SYNOPSIS
        Creates a new file share.
    
    .DESCRIPTION
        Creates a new file share (NFS or SMB) in a specified sub-project.
        Supports waiting for the creation to complete via the -Wait switch.
    
    .PARAMETER Name
        The name for the file share. Required.
    
    .PARAMETER SubprojectId
        The sub-project ID to create the file share in. Required.
    
    .PARAMETER SizeGB
        The size of the file share in GB. Defaults to 100.
    
    .PARAMETER Protocol
        The protocol for the file share. Valid values: NFS, SMB. Defaults to NFS.
    
    .PARAMETER Wait
        If specified, waits for the file share creation to complete.
    
    .EXAMPLE
        PS> New-CloudFileShare -Name "MyShare" -SubprojectId "subproject-..." -SizeGB 500 -Protocol NFS
        
        Creates a 500GB NFS file share.
    
    .EXAMPLE
        PS> New-CloudFileShare -Name "WindowsShare" -SubprojectId "subproject-..." -Protocol SMB -Wait
        
        Creates an SMB file share and waits for completion.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [int]$SizeGB = 100,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('NFS', 'SMB')]
        [string]$Protocol = 'NFS',
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        $body = @{
            name = $Name
            subprojectId = $SubprojectId
            sizeGB = $SizeGB
            protocol = $Protocol
        }
        
        if (-not $PSCmdlet.ShouldProcess("file share '$Name' ($SizeGB GB, $Protocol)", 'Create')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'storage/file-shares' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to create file share: $($_.Exception.Message)"
        return $null
    }
}
