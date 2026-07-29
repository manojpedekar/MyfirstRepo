function Resize-CloudInstance {
    <#
    .SYNOPSIS
        Changes the CPU and memory allocation of an instance.
    
    .DESCRIPTION
        Resizes a cloud instance to change its CPU and memory allocation.
        Some cloud providers require the instance to be powered off for resizing.
        
        Note: CPU must typically be a power of 2 (1, 2, 4, 8, 16, etc.) on some clouds.
    
    .PARAMETER Id
        The unique identifier of the instance to resize. This parameter is mandatory.
    
    .PARAMETER Cpu
        The new number of CPU cores. Must be a positive integer.
    
    .PARAMETER Memory
        The new amount of memory in GB. Must be a positive integer.
    
    .PARAMETER Force
        If specified, attempts to resize even if the instance is powered on.
        Note: This may fail on some clouds that require powered-off resizing.
    
    .PARAMETER Wait
        If specified, waits for the resize operation to complete before returning.
    
    .PARAMETER Async
        If specified, returns immediately after starting the resize operation.
        Returns the operation/job object for tracking.
    
    .EXAMPLE
        PS> Resize-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Cpu 4 -Memory 8
        
        Resizes the instance to 4 CPU cores and 8 GB RAM.
    
    .EXAMPLE
        PS> Resize-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Cpu 8 -Memory 16 -Force -Wait
        
        Resizes a running instance and waits for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 64)]
        [int]$Cpu,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 512)]
        [int]$Memory,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    process {
        try {
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            
            # Validate instance exists
            $instance = Get-CloudInstance -Id $Id
            if (-not $instance) {
                Write-Error "Instance '$Id' not found"
                return $null
            }
            
            # Validate at least one resize parameter is specified
            if (-not $Cpu -and -not $Memory) {
                Write-Error "Either Cpu or Memory must be specified"
                return $null
            }
            
            # Validate CPU is power of 2 if specified (common cloud requirement)
            if ($Cpu -and -not $Force) {
                $isPowerOfTwo = ($Cpu -ne 0) -and (($Cpu -band ($Cpu - 1)) -eq 0)
                if (-not $isPowerOfTwo) {
                    Write-Warning "CPU count of $Cpu is not a power of 2. Some clouds require power of 2 values (1, 2, 4, 8, 16, etc.). Use -Force to override this warning."
                }
            }
            
            # Build request body
            $body = @{}
            if ($Cpu) { $body['cpu'] = $Cpu }
            if ($Memory) { $body['memory'] = $Memory }
            if ($Force) { $body['force'] = $true }
            
            # Build invoke parameters
            $invokeParams = @{
                Path = "compute/instances/$Id/resize"
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
            Write-Error "Failed to resize instance: $($_.Exception.Message)"
            return $null
        }
    }
}
