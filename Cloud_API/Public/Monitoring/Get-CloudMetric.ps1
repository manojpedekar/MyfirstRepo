function Get-CloudMetric {
    <#
    .SYNOPSIS
        Retrieves metrics from the cloud platform.
    
    .DESCRIPTION
        Gets metrics data for resources in the SS&C Cloud platform. Supports
        filtering by resource, metric type, date range, and interval.
    
    .PARAMETER ResourceId
        The ID of the resource to get metrics for.
    
    .PARAMETER Metric
        The specific metric to retrieve (e.g., 'CPU', 'MEMORY', 'DISK').
    
    .PARAMETER StartDate
        The start date for the metrics query.
    
    .PARAMETER EndDate
        The end date for the metrics query.
    
    .PARAMETER Interval
        The aggregation interval (e.g., '1m', '5m', '1h', '1d').
    
    .EXAMPLE
        PS> Get-CloudMetric -ResourceId "i-12345" -Metric "CPU" `
             -StartDate (Get-Date).AddHours(-1) -Interval "5m"
        
        Retrieves CPU metrics for the last hour, aggregated every 5 minutes.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [Alias('Id')]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('CPU', 'MEMORY', 'DISK', 'NETWORK', 'DISK_IO', 'CONNECTIONS')]
        [string]$Metric,
        
        [Parameter(Mandatory=$false)]
        [DateTime]$StartDate,
        
        [Parameter(Mandatory=$false)]
        [DateTime]$EndDate,
        
        [Parameter(Mandatory=$false)]
        [ValidatePattern('^\d+[smhdw]$')]
        [string]$Interval
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Build query parameters
            $queryParams = @{}
            
            if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
            if ($Metric) { $queryParams['metric'] = $Metric }
            if ($StartDate) { $queryParams['startDate'] = $StartDate.ToString('o') }
            if ($EndDate) { $queryParams['endDate'] = $EndDate.ToString('o') }
            if ($Interval) { $queryParams['interval'] = $Interval }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path 'metrics' -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve metrics: $($_.Exception.Message)"
            return $null
        }
    }
}
