function New-CloudAlert {
    <#
    .SYNOPSIS
        Creates a new alert rule in the cloud platform.
    
    .DESCRIPTION
        Creates a new alert rule that monitors a metric for a resource and
        triggers when the specified threshold is crossed.
    
    .PARAMETER Name
        The name for the alert rule. Required.
    
    .PARAMETER ResourceType
        The type of resource to monitor (e.g., 'Instance', 'Volume', 'LoadBalancer').
    
    .PARAMETER ResourceId
        The ID of the specific resource to monitor. If not specified, monitors
        all resources of the specified type.
    
    .PARAMETER Metric
        The metric to monitor (e.g., 'CPU', 'MEMORY', 'DISK', 'NETWORK').
    
    .PARAMETER Threshold
        The threshold value that triggers the alert.
    
    .PARAMETER Operator
        The comparison operator (e.g., 'GREATER_THAN', 'LESS_THAN', 'EQUALS').
    
    .PARAMETER Wait
        If specified, waits for the alert rule creation to complete.
    
    .EXAMPLE
        PS> New-CloudAlert -Name "High CPU Alert" -ResourceType "Instance" `
             -Metric "CPU" -Threshold 80 -Operator "GREATER_THAN"
        
        Creates an alert rule that triggers when CPU exceeds 80%.
    
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
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('CPU', 'MEMORY', 'DISK', 'NETWORK', 'DISK_IO', 'CONNECTIONS')]
        [string]$Metric,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(0, 100)]
        [int]$Threshold,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('GREATER_THAN', 'LESS_THAN', 'EQUALS', 'GREATER_THAN_OR_EQUALS', 'LESS_THAN_OR_EQUALS')]
        [string]$Operator,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
        }
        
        if ($ResourceType) { $body['resourceType'] = $ResourceType }
        if ($ResourceId) { $body['resourceId'] = $ResourceId }
        if ($Metric) { $body['metric'] = $Metric }
        if ($PSBoundParameters.ContainsKey('Threshold')) { $body['threshold'] = $Threshold }
        if ($Operator) { $body['operator'] = $Operator }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path 'alerts' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait
        
        return $response
    }
    catch {
        Write-Error "Failed to create alert rule: $($_.Exception.Message)"
        return $null
    }
}
