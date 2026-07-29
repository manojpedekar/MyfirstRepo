function Get-CloudAlert {
    <#
    .SYNOPSIS
        Retrieves alerts from the cloud platform.
    
    .DESCRIPTION
        Gets alerts from the SS&C Cloud platform. Can retrieve a specific alert
        by ID or list all alerts with optional filtering by status, severity,
        resource, and date range.
    
    .PARAMETER Id
        The unique identifier of the alert to retrieve.
    
    .PARAMETER Status
        Filter alerts by status (e.g., 'ACTIVE', 'RESOLVED', 'ACKNOWLEDGED').
    
    .PARAMETER Severity
        Filter alerts by severity (e.g., 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW').
    
    .PARAMETER ResourceId
        Filter alerts by the resource ID they are associated with.
    
    .PARAMETER StartDate
        Filter alerts created after this date.
    
    .PARAMETER EndDate
        Filter alerts created before this date.
    
    .EXAMPLE
        PS> Get-CloudAlert
        
        Retrieves all alerts.
    
    .EXAMPLE
        PS> Get-CloudAlert -Id "alert-12345"
        
        Retrieves details for a specific alert.
    
    .EXAMPLE
        PS> Get-CloudAlert -Status 'ACTIVE' -Severity 'HIGH'
        
        Retrieves all active high-severity alerts.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('AlertId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('ACTIVE', 'RESOLVED', 'ACKNOWLEDGED', 'SUPPRESSED')]
        [string]$Status,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')]
        [string]$Severity,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId,
        
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
                sort = 'createdAt,desc'
            }
            
            if ($Status) { $queryParams['status'] = $Status }
            if ($Severity) { $queryParams['severity'] = $Severity }
            if ($ResourceId) { $queryParams['resourceId'] = $ResourceId }
            if ($StartDate) { $queryParams['startDate'] = $StartDate.ToString('o') }
            if ($EndDate) { $queryParams['endDate'] = $EndDate.ToString('o') }
            
            # Determine path
            if ($Id) {
                $path = "alerts/$Id"
            } else {
                $path = 'alerts'
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve alert(s): $($_.Exception.Message)"
            return $null
        }
    }
}
