function Get-CloudAlertHistory {
    <#
    .SYNOPSIS
        Retrieves the history of alert triggers.
    
    .DESCRIPTION
        Gets the historical record of when alerts were triggered, acknowledged,
        and resolved. Useful for analyzing alert patterns and SLA compliance.
    
    .PARAMETER AlertId
        The ID of the alert to get history for.
    
    .PARAMETER StartDate
        Filter history entries after this date.
    
    .PARAMETER EndDate
        Filter history entries before this date.
    
    .EXAMPLE
        PS> Get-CloudAlertHistory -AlertId "alert-123" -StartDate (Get-Date).AddDays(-7)
        
        Retrieves alert history for the last 7 days.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('Id')]
        [string]$AlertId,
        
        [Parameter(Mandatory=$false)]
        [DateTime]$StartDate,
        
        [Parameter(Mandatory=$false)]
        [DateTime]$EndDate
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'timestamp,desc'
            }
            
            if ($StartDate) { $queryParams['startDate'] = $StartDate.ToString('o') }
            if ($EndDate) { $queryParams['endDate'] = $EndDate.ToString('o') }
            
            # Determine path
            if ($AlertId) {
                $path = "alerts/$AlertId/history"
            } else {
                $path = 'alerts/history'
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve alert history: $($_.Exception.Message)"
            return $null
        }
    }
}
