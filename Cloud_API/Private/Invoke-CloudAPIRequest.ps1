function Invoke-CloudAPIRequest {
    <#
    .SYNOPSIS
        Centralized API request handler with retry logic, error handling, and pagination support.
    
    .DESCRIPTION
        Handles all API requests to the SS&C Cloud API. This function:
        - Builds URLs from the base URI + path
        - Adds query parameters with proper URL encoding
        - Converts body to JSON with depth 10
        - Implements retry logic with configurable attempts
        - Handles pagination automatically (retrieves ALL pages)
        - Supports async operations via -Async and -Wait switches
        - Returns $null on failure with non-terminating errors
    
    .PARAMETER Path
        The API path (e.g., "compute/instances", "network/securitygroups").
    
    .PARAMETER Method
        The HTTP method: GET, POST, PUT, DELETE, or PATCH.
    
    .PARAMETER Headers
        Hashtable of headers to include in the request.
    
    .PARAMETER Body
        The request body object (will be converted to JSON).
    
    .PARAMETER QueryParameters
        Hashtable of query parameters to add to the URL.
    
    .PARAMETER Async
        If specified, returns immediately after making the request without waiting for completion.
        Returns the job/operation object for tracking.
    
    .PARAMETER Wait
        If specified, waits for async operations to complete before returning.
    
    .PARAMETER Timeout
        Timeout in seconds for -Wait operations. Default is 300 seconds (5 minutes).
    
    .PARAMETER ContentType
        The content type for the request. Default is 'application/json'.
    
    .PARAMETER SkipPagination
        If specified, does not automatically retrieve all pages for paginated responses.
    
    .EXAMPLE
        PS> $headers = New-CloudAPIHeaders
        PS> $response = Invoke-CloudAPIRequest -Path "compute/instances" -Method 'GET' -Headers $headers
        
        Retrieves all instances (with automatic pagination).
    
    .EXAMPLE
        PS> $headers = New-CloudAPIHeaders -IncludeContentType
        PS> $body = @{ name = "NewInstance"; cpu = 2; memory = 4 }
        PS> Invoke-CloudAPIRequest -Path "compute/instances" -Method 'POST' -Headers $headers -Body $body -Wait
        
        Creates a new instance and waits for the operation to complete.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject (the response content), or $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Headers = @{},
        
        [Parameter(Mandatory=$false)]
        [object]$Body = $null,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$QueryParameters = @{},
        
        [Parameter(Mandatory=$false)]
        [switch]$Async,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [int]$Timeout = 300,
        
        [Parameter(Mandatory=$false)]
        [string]$ContentType = 'application/json',
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipPagination
    )
    
    # Build base URL
    $baseUri = $script:ModuleConfig.BaseUri
    $apiVersion = $script:ModuleConfig.ApiVersion
    $uri = "$baseUri/api/$apiVersion/$Path"
    
    # Add query parameters with URL encoding
    if ($QueryParameters.Count -gt 0) {
        $queryParts = @()
        foreach ($key in $QueryParameters.Keys) {
            $encodedValue = [System.Web.HttpUtility]::UrlEncode($QueryParameters[$key])
            $queryParts += "$key=$encodedValue"
        }
        $queryString = $queryParts -join '&'
        $uri = "$uri`?$queryString"
    }
    
    # Convert body to JSON if provided
    $bodyJson = $null
    if ($null -ne $Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 10
    }
    
    # Set up retry logic
    $attempt = 0
    $maxAttempts = $script:ModuleConfig.MaxRetries
    $retryDelay = $script:ModuleConfig.RetryDelaySeconds
    
    do {
        $attempt++
        $success = $false
        
        try {
            Write-Verbose "Making $Method request to $uri (Attempt $attempt of $maxAttempts)"
            
            # Make the request
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $Headers -Body $bodyJson -ContentType $ContentType -ErrorAction Stop
            $success = $true
            
            # Handle pagination
            if (-not $SkipPagination -and $response.content -is [array] -and $response.totalElements -gt 0) {
                $allContent = @($response.content)
                $totalElements = $response.totalElements
                $pageSize = $response.size
                $totalPages = [math]::Ceiling($totalElements / $pageSize)
                
                if ($totalPages -gt 1) {
                    Write-Verbose "Pagination detected: $totalElements total elements across $totalPages pages"
                    
                    for ($page = 1; $page -lt $totalPages; $page++) {
                        $pageQuery = @{'page' = $page}
                        # Add existing query parameters
                        foreach ($key in $QueryParameters.Keys) {
                            $pageQuery[$key] = $QueryParameters[$key]
                        }
                        
                        $pageUri = "$baseUri/api/$apiVersion/$Path"
                        $pageQueryParts = @()
                        foreach ($key in $pageQuery.Keys) {
                            $encodedValue = [System.Web.HttpUtility]::UrlEncode($pageQuery[$key])
                            $pageQueryParts += "$key=$encodedValue"
                        }
                        $pageQueryString = $pageQueryParts -join '&'
                        $pageUri = "$pageUri`?$pageQueryString"
                        
                        Write-Verbose "Retrieving page $($page + 1) of $totalPages"
                        $pageResponse = Invoke-RestMethod -Uri $pageUri -Method $Method -Headers $Headers -ContentType $ContentType -ErrorAction Stop
                        
                        if ($pageResponse.content) {
                            $allContent += $pageResponse.content
                        }
                    }
                    
                    Write-Verbose "Retrieved $($allContent.Count) of $totalElements total elements"
                    return $allContent
                }
            }
            
            # Handle async operations
            if ($Wait -and $response.id -and ($response.status -or $response.state)) {
                $jobId = $response.id
                Write-Verbose "Waiting for async operation to complete: $jobId"
                
                $startTime = Get-Date
                $completed = $false
                $maxIterations = [math]::Ceiling($Timeout / 5)  # 5-second sleep intervals
                $iteration = 0
                
                do {
                    $iteration++
                    Start-Sleep -Seconds 5
                    $elapsed = ((Get-Date) - $startTime).TotalSeconds
                    
                    # Check timeout
                    if ($elapsed -gt $Timeout) {
                        Write-Warning "Timeout waiting for operation $jobId to complete after $Timeout seconds"
                        break
                    }
                    
                    # Check max iterations as safeguard
                    if ($iteration -ge $maxIterations) {
                        Write-Warning "Maximum wait iterations ($maxIterations) reached for operation $jobId"
                        break
                    }
                    
                    # Check job status
                    try {
                        $jobStatus = Invoke-CloudAPIRequest -Path "management/jobs/$jobId" -Method 'GET' -Headers $Headers -SkipPagination
                        
                        if ($null -eq $jobStatus) {
                            Write-Verbose "Job status returned null, assuming operation completed"
                            $completed = $true
                        }
                        elseif ($jobStatus.status -eq 'COMPLETED' -or $jobStatus.status -eq 'SUCCESS' -or $jobStatus.state -eq 'available') {
                            $completed = $true
                            Write-Verbose "Operation $jobId completed successfully (elapsed: $([math]::Round($elapsed))s)"
                        }
                        elseif ($jobStatus.status -eq 'FAILED' -or $jobStatus.status -eq 'ERROR') {
                            Write-Error "Operation $jobId failed after $([math]::Round($elapsed))s : $($jobStatus.errorMessage)"
                            return $null
                        }
                        elseif ($jobStatus.status -eq 'CANCELLED') {
                            Write-Warning "Operation $jobId was cancelled after $([math]::Round($elapsed))s"
                            return $null
                        }
                        else {
                            Write-Verbose "Operation $jobId status: $($jobStatus.status) (iteration $iteration, elapsed: $([math]::Round($elapsed))s)"
                        }
                    }
                    catch {
                        Write-Verbose "Could not retrieve job status: $($_.Exception.Message)"
                        $completed = $true
                    }
                } while (-not $completed)
                
                # Return final status
                if (-not $completed) {
                    Write-Warning "Operation $jobId wait ended without confirmed completion"
                    return [PSCustomObject]@{
                        Id = $jobId
                        Status = 'TIMEOUT'
                        ElapsedSeconds = [math]::Round($elapsed)
                    }
                }
            }
            
            # Return response content
            if ($response.content) {
                return $response.content
            } else {
                return $response
            }
        }
        catch {
            $errorDetails = Format-CloudAPIError -Exception $_.Exception
            $statusCode = $errorDetails.StatusCode
            
            # Check if we should retry
            if ($attempt -lt $maxAttempts -and $statusCode -in @(429, 500, 502, 503, 504)) {
                Write-Warning "Request failed with status $statusCode. Retrying in $retryDelay seconds... (Attempt $attempt of $maxAttempts)"
                Start-Sleep -Seconds $retryDelay
            } else {
                # Don't retry - write error and return null
                Write-Error -Message "API request failed to $uri : $($errorDetails.Message)" -ErrorId $statusCode
                return $null
            }
        }
    } while (-not $success -and $attempt -lt $maxAttempts)
    
    # If we exhausted retries
    if (-not $success) {
        Write-Error "API request failed after $maxAttempts attempts"
        return $null
    }
}
