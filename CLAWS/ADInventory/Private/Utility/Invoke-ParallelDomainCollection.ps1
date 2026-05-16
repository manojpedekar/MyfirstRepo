function Invoke-ParallelDomainCollection {
    <#
    .SYNOPSIS
        Processes multiple domains concurrently using PowerShell runspaces

    .DESCRIPTION
        Enables parallel domain processing to significantly reduce total collection time
        for multi-domain inventories. Uses runspace pools to execute domain collections
        concurrently while maintaining thread safety.

        NEW FEATURE - Not in original script:
        - Concurrent domain processing
        - Configurable parallelism level
        - Thread-safe result aggregation
        - Progress monitoring across all domains

    .PARAMETER Domains
        Array of domain names to process concurrently

    .PARAMETER ScriptBlock
        The script block to execute for each domain.
        Receives the following parameters in order:
        1. Domain name (string)
        2. Domain index (1-based int) - position in the processing order
        3. Total domains (int) - total number of domains being processed
        4+ Additional arguments from ArgumentList

    .PARAMETER ThrottleLimit
        Maximum number of concurrent domain collections (default: 4)
        Recommended: Number of domains or CPU cores, whichever is smaller

    .PARAMETER ArgumentList
        Additional arguments to pass to the script block
        Domain name is always passed as first argument

    .PARAMETER TimeoutMinutes
        Timeout in minutes for each domain collection (default: 60)

    .OUTPUTS
        Array of PSCustomObject with properties:
        - Domain: Domain name
        - Success: Boolean indicating success/failure
        - Result: Result from script block (if success)
        - Error: Error message (if failed)
        - DurationSeconds: Time taken to process domain

    .EXAMPLE
        # Collect from multiple domains in parallel
        $domains = @('contoso.com', 'fabrikam.com', 'trusted.com')
        $scriptBlock = {
            param($domain, $domainIndex, $totalDomains, $config, $outputPath)
            Write-Host "Processing domain $domainIndex of $totalDomains : $domain"
            # Domain collection logic here
            Get-ADInventoryObject -Server $domain -Config $config
        }
        $results = Invoke-ParallelDomainCollection `
            -Domains $domains `
            -ScriptBlock $scriptBlock `
            -ThrottleLimit 3 `
            -ArgumentList $config, $outputPath

    .EXAMPLE
        # Process with timeout
        $results = Invoke-ParallelDomainCollection `
            -Domains $domains `
            -ScriptBlock $scriptBlock `
            -ThrottleLimit 2 `
            -TimeoutMinutes 30

    .NOTES
        Part of SSNC.ADInventory module

        Performance Considerations:
        - Ideal for 3+ domains
        - Each domain uses separate runspace
        - Consider network bandwidth and DC load
        - Recommended ThrottleLimit: 4-8 for most scenarios

        Thread Safety:
        - Each domain collection is isolated in its own runspace
        - Results are aggregated after all complete
        - No shared state between runspaces

        Memory Usage:
        - Each runspace has memory overhead (~50MB)
        - Monitor memory with large domain counts
        - Consider sequential processing for memory-constrained environments

        Error Handling:
        - Individual domain failures don't stop others
        - Timeouts handled gracefully
        - All errors captured in results
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domains,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 32)]
        [int]$ThrottleLimit = 4,

        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @(),

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1440)]
        [int]$TimeoutMinutes = 60
    )

    process {
        Write-ADInventoryLog -Level Info -Message "Starting parallel domain collection" `
            -Context @{
                DomainCount = $Domains.Count
                ThrottleLimit = $ThrottleLimit
                TimeoutMinutes = $TimeoutMinutes
            }

        # Validate we have domains to process
        if ($Domains.Count -eq 0) {
            Write-ADInventoryLog -Level Warning -Message "No domains to process"
            return @()
        }

        # If only one domain, don't bother with parallelism
        if ($Domains.Count -eq 1) {
            Write-ADInventoryLog -Level Debug -Message "Single domain - using sequential processing"

            $startTime = Get-Date
            try {
                # Pass domain, domainIndex (1), totalDomains (1), then additional args
                $result = & $ScriptBlock $Domains[0] 1 1 @ArgumentList
                $success = $true
                $error = $null
            }
            catch {
                $result = $null
                $success = $false
                $error = $_.Exception.Message
            }
            $duration = ((Get-Date) - $startTime).TotalSeconds

            return @([PSCustomObject]@{
                Domain = $Domains[0]
                Success = $success
                Result = $result
                Error = $error
                DurationSeconds = [Math]::Round($duration, 2)
            })
        }

        # Adjust throttle limit if more than domain count
        if ($ThrottleLimit -gt $Domains.Count) {
            $ThrottleLimit = $Domains.Count
            Write-ADInventoryLog -Level Debug -Message "Adjusted throttle limit to domain count" `
                -Context @{ ThrottleLimit = $ThrottleLimit }
        }

        # Create runspace pool
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
        $runspacePool.Open()

        Write-ADInventoryLog -Level Debug -Message "Runspace pool created" `
            -Context @{
                MinRunspaces = 1
                MaxRunspaces = $ThrottleLimit
            }

        $jobs = [System.Collections.ArrayList]::new()

        try {
            # Create a job for each domain
            $totalDomains = $Domains.Count
            for ($i = 0; $i -lt $Domains.Count; $i++) {
                $domain = $Domains[$i]
                $domainIndex = $i + 1  # 1-based index for display

                Write-ADInventoryLog -Level Verbose -Message "Creating runspace for domain" `
                    -Context @{ Domain = $domain; Index = $domainIndex; Total = $totalDomains }

                # Create PowerShell instance
                $ps = [powershell]::Create()
                $ps.RunspacePool = $runspacePool

                # Add script block
                [void]$ps.AddScript($ScriptBlock)

                # Add parameters: domain, domainIndex, totalDomains, then additional args
                [void]$ps.AddArgument($domain)
                [void]$ps.AddArgument($domainIndex)
                [void]$ps.AddArgument($totalDomains)
                foreach ($arg in $ArgumentList) {
                    [void]$ps.AddArgument($arg)
                }

                # Start async execution
                $handle = $ps.BeginInvoke()

                # Store job info
                [void]$jobs.Add([PSCustomObject]@{
                    Domain = $domain
                    DomainIndex = $domainIndex
                    PowerShell = $ps
                    Handle = $handle
                    StartTime = Get-Date
                })
            }

            Write-ADInventoryLog -Level Info -Message "All runspaces started" `
                -Context @{ JobCount = $jobs.Count }

            # Wait for all jobs to complete (with timeout)
            $results = [System.Collections.ArrayList]::new()
            $timeoutSeconds = $TimeoutMinutes * 60
            $completedCount = 0
            $lastProgressUpdate = Get-Date

            while ($completedCount -lt $jobs.Count) {
                foreach ($job in $jobs) {
                    # Skip already processed jobs
                    if ($job.Completed) {
                        continue
                    }

                    # Check if completed
                    if ($job.Handle.IsCompleted) {
                        $duration = ((Get-Date) - $job.StartTime).TotalSeconds

                        try {
                            # Get result
                            $result = $job.PowerShell.EndInvoke($job.Handle)
                            $success = $true
                            $errorMsg = $null

                            # Check for errors in the streams
                            if ($job.PowerShell.Streams.Error.Count -gt 0) {
                                $errorMsg = ($job.PowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
                                Write-ADInventoryLog -Level Warning -Message "Domain processing completed with errors" `
                                    -Context @{
                                        Domain = $job.Domain
                                        ErrorCount = $job.PowerShell.Streams.Error.Count
                                    }
                            }

                            Write-ADInventoryLog -Level Info -Message "Domain processing completed" `
                                -Context @{
                                    Domain = $job.Domain
                                    DurationSeconds = [Math]::Round($duration, 2)
                                    Success = $success
                                }
                        }
                        catch {
                            $result = $null
                            $success = $false
                            $errorMsg = $_.Exception.Message

                            Write-ADInventoryLog -Level Error -Message "Domain processing failed" `
                                -Context @{
                                    Domain = $job.Domain
                                    DurationSeconds = [Math]::Round($duration, 2)
                                } `
                                -Exception $_.Exception
                        }

                        # Add to results
                        [void]$results.Add([PSCustomObject]@{
                            Domain = $job.Domain
                            Success = $success
                            Result = $result
                            Error = $errorMsg
                            DurationSeconds = [Math]::Round($duration, 2)
                        })

                        # Mark as completed
                        $job | Add-Member -NotePropertyName 'Completed' -NotePropertyValue $true -Force
                        $completedCount++

                        # Cleanup PowerShell instance
                        $job.PowerShell.Dispose()
                    }
                    # Check for timeout
                    elseif (((Get-Date) - $job.StartTime).TotalSeconds -gt $timeoutSeconds) {
                        $duration = ((Get-Date) - $job.StartTime).TotalSeconds

                        Write-ADInventoryLog -Level Error -Message "Domain processing timed out" `
                            -Context @{
                                Domain = $job.Domain
                                TimeoutMinutes = $TimeoutMinutes
                            }

                        # Stop the runspace
                        try {
                            $job.PowerShell.Stop()
                        }
                        catch {
                            Write-ADInventoryLog -Level Warning -Message "Failed to stop timed-out runspace" `
                                -Exception $_.Exception
                        }

                        # Add timeout result
                        [void]$results.Add([PSCustomObject]@{
                            Domain = $job.Domain
                            Success = $false
                            Result = $null
                            Error = "Operation timed out after $TimeoutMinutes minutes"
                            DurationSeconds = [Math]::Round($duration, 2)
                        })

                        $job | Add-Member -NotePropertyName 'Completed' -NotePropertyValue $true -Force
                        $completedCount++

                        # Cleanup PowerShell instance
                        $job.PowerShell.Dispose()
                    }
                }

                # Progress update every 5 seconds
                if (((Get-Date) - $lastProgressUpdate).TotalSeconds -gt 5) {
                    Write-ADInventoryLog -Level Info -Message "Parallel collection progress" `
                        -Context @{
                            Completed = $completedCount
                            Total = $jobs.Count
                            PercentComplete = [Math]::Round(($completedCount / $jobs.Count) * 100, 1)
                        }
                    $lastProgressUpdate = Get-Date
                }

                # Sleep briefly to avoid busy-wait
                if ($completedCount -lt $jobs.Count) {
                    Start-Sleep -Milliseconds 100
                }
            }

            Write-ADInventoryLog -Level Info -Message "Parallel domain collection completed" `
                -Context @{
                    TotalDomains = $Domains.Count
                    SuccessfulDomains = ($results | Where-Object { $_.Success }).Count
                    FailedDomains = ($results | Where-Object { -not $_.Success }).Count
                    TotalDurationSeconds = [Math]::Round((($results | Measure-Object -Property DurationSeconds -Sum).Sum), 2)
                }

            return $results.ToArray()
        }
        catch {
            Write-ADInventoryLog -Level Error -Message "Parallel collection framework failed" `
                -Exception $_.Exception

            throw
        }
        finally {
            # Cleanup any remaining PowerShell instances
            foreach ($job in $jobs) {
                if (-not $job.Completed -and $job.PowerShell) {
                    try {
                        $job.PowerShell.Dispose()
                    }
                    catch {
                        # Best effort cleanup
                    }
                }
            }

            # Close runspace pool
            if ($runspacePool) {
                $runspacePool.Close()
                $runspacePool.Dispose()
            }

            Write-ADInventoryLog -Level Debug -Message "Runspace pool cleaned up"
        }
    }
}
