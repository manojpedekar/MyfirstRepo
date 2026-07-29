function New-CloudAffinityRule {
    <#
    .SYNOPSIS
        Creates a new affinity or anti-affinity rule.
    
    .DESCRIPTION
        Creates an affinity rule to keep instances on the same host, or an
        anti-affinity rule to keep instances on different hosts for high availability.
    
    .PARAMETER Name
        A descriptive name for the affinity rule.
    
    .PARAMETER Type
        The type of affinity rule: "Affinity" or "AntiAffinity". This parameter is mandatory.
    
    .PARAMETER InstanceIds
        Array of instance IDs to include in the rule. At least one instance is required.
    
    .PARAMETER SubprojectId
        The sub-project ID where the rule will be created.
    
    .PARAMETER Enabled
        Whether the rule is enabled. Default is $true.
    
    .PARAMETER Wait
        If specified, waits for the rule creation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the rule creation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> New-CloudAffinityRule -Name "WebServers-AntiAffinity" -Type "AntiAffinity" -InstanceIds @("i-1...", "i-2...", "i-3...")
        
        Creates an anti-affinity rule to keep web servers on different hosts.
    
    .EXAMPLE
        PS> New-CloudAffinityRule -Name "Database-Affinity" -Type "Affinity" -InstanceIds @("i-db1...", "i-db2...") -SubprojectId "subproject-..." -Wait
        
        Creates an affinity rule and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Affinity', 'AntiAffinity')]
        [string]$Type,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$InstanceIds,
        
        [Parameter(Mandatory=$false)]
        [string]$SubprojectId,
        
        [Parameter(Mandatory=$false)]
        [bool]$Enabled = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        # Validate instances exist
        foreach ($instanceId in $InstanceIds) {
            $instanceExists = Test-CloudAPIResource -ResourceType 'compute/instances' -ResourceId $instanceId
            if (-not $instanceExists) {
                Write-Error "Instance '$instanceId' not found"
                return $null
            }
        }
        
        # Build request body
        $body = @{
            type = $Type
            instanceIds = $InstanceIds
            enabled = $Enabled
        }
        
        if ($Name) { $body['name'] = $Name }
        if ($SubprojectId) { $body['subprojectId'] = $SubprojectId }
        
        # Build invoke parameters
        $invokeParams = @{
            Path = "compute/affinity-rules"
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
        Write-Error "Failed to create affinity rule: $($_.Exception.Message)"
        return $null
    }
}
