function Resume-CloudJob {
    <#
    .SYNOPSIS
        Retries a stuck cloud job.
    
    .DESCRIPTION
        Retries a stuck or failed job in the SS&C Cloud.
    
    .PARAMETER Id
        The unique identifier of the job. Required.
    
    .EXAMPLE
        PS> Resume-CloudJob -Id "job-00000000-0000-0000-0000-0000000000000"
        
        Retries the specified job.
    
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
        [Alias('JobId')]
        [string]$Id
    )
    
    try {
        if (-not $PSCmdlet.ShouldProcess("job '$Id'", 'Resume')) {
            return $null
        }
        
        $headers = New-CloudAPIHeaders -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "management/jobs/$Id" -Method 'POST' -Headers $headers
        
        return $response
    }
    catch {
        Write-Error "Failed to resume job: $($_.Exception.Message)"
        return $null
    }
}
