<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	6/27/2024 10:41 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A comparison of regular ForEach-Object loop to workflows, runspace, jobs and powershell 7 ForEach-Object -Parallel
#>


Function Test-DomainControllersPS7 {
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5
	)
	
	# Check if the PowerShell version is 7.0 or higher
	If ($PSVersionTable.PSVersion.Major -lt 7) {
		Throw "This function requires PowerShell 7.0 or higher."
	}
	
	# Use the pipeline to process each domain controller in parallel
	$DomainControllers | ForEach-Object -Parallel {
		$DC = $_
		Try {
			# Attempt to ping the domain controller
			$result = Test-Connection -ComputerName $DC -Count 1 -ErrorAction Stop
			
			#count the number of enabled users in Active Directory on the Specific domain controllers
			$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $DC).Count
			
			[PSCustomObject]@{
				Server    = $DC
				Status    = 'Online'
				Response  = $result.ResponseTime
				UserCount = $usercount
			}
		} Catch {
			[PSCustomObject]@{
				Server    = $DC
				Status    = 'Offline'
				Response  = 'N/A'
				UserCount = 'N/A'
			}
		}
	} -ThrottleLimit $ThrottleLimit
}

Function Test-DomainControllersRS {
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5,
		[switch]$Max
	)
	
	If ($Max) {
		$ThrottleLimit = $DomainControllers.Count
	}
	
	$runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
	$runspacePool.Open()
	
	$runspaces = @()
	ForEach ($DC In $DomainControllers) {
		$powershell = [powershell]::Create().AddScript({
				Param ($DC)
				Try {
					# Attempt to ping the domain controller
					$result = Test-Connection -ComputerName $DC -Count 1 -ErrorAction Stop
					
					#count the number of enabled users in Active Directory on the Specific domain controllers
					$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $DC).Count
					
					[PSCustomObject]@{
						Server    = $DC
						Status    = 'Online'
						Response  = $result.ResponseTime
						UserCount = $usercount
					}
				} Catch {
					[PSCustomObject]@{
						Server    = $DC
						Status    = 'Offline'
						Response  = 'N/A'
						UserCount = 'N/A'
					}
				}
			}).AddArgument($DC)
		$powershell.RunspacePool = $runspacePool
		$runspaces += [PSCustomObject]@{
			Pipe   = $powershell
			Status = $powershell.BeginInvoke()
		}
	}
	
	ForEach ($runspace In $runspaces) {
		$runspace.Pipe.EndInvoke($runspace.Status)
		$runspace.Pipe.Dispose()
	}
	
	$runspacePool.Close()
	$runspacePool.Dispose()
	
	Return $runspaces.Pipe | ForEach-Object { $_.Streams.Error.ReadAll() }
}

Function Test-DomainControllersJob {
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5
	)
	
	$jobs = @()
	ForEach ($DC In $DomainControllers) {
		# Start new job only if the number of running jobs is less than the maximum allowed
		While ((Get-Job -State Running).Count -ge $ThrottleLimit) {
			Start-Sleep -Seconds 1 # Wait for some time before checking again
		}
		
		$job = Start-Job -ScriptBlock {
			Param ($DC)
			Try {
				# Attempt to ping the domain controller
				$result = Test-Connection -ComputerName $DC -Count 1 -ErrorAction Stop
				
				#count the number of enabled users in Active Directory on the Specific domain controllers
				$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $DC).Count
				
				[PSCustomObject]@{
					Server    = $DC
					Status    = 'Online'
					Response  = $result.ResponseTime
					UserCount = $usercount
				}
			} Catch {
				[PSCustomObject]@{
					Server    = $DC
					Status    = 'Offline'
					Response  = 'N/A'
					UserCount = 'N/A'
				}
			}
		} -ArgumentList $DC
		$jobs += $job
	}
	
	# Wait for all jobs to complete and collect results
	$results = $jobs | Wait-Job | Receive-Job
	
	# Clean up the jobs
	$jobs | Remove-Job
	
	Return $results
}

Function Test-DomainControllers {
	Param (
		[String[]]$DomainControllers
	)
	
	# Process each domain controller in serial
	ForEach ($DC In $DomainControllers) {
		Try {
			# Attempt to ping the domain controller
			$result = Test-Connection -ComputerName $DC -Count 1 -ErrorAction Stop
			
			#count the number of enabled users in Active Directory on the Specific domain controllers
			$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $DC).Count
			
			[PSCustomObject]@{
				Server    = $DC
				Status    = 'Online'
				Response  = $result.ResponseTime
				UserCount = $usercount
			}
		} Catch {
			# Handle any errors, such as unreachable server
			[PSCustomObject]@{
				Server    = $DC
				Status    = 'Offline'
				Response  = 'N/A'
				UserCount = 'N/A'
			}
		}
	}
}

# Define the workflow
Workflow Test-DomainControllersWF {
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5
	)
	
	# Process each domain controller in parallel
	ForEach -ThrottleLimit $ThrottleLimit -parallel ($DC In $DomainControllers) {
		# Use InlineScript to run commands that are not supported directly in workflows
		InlineScript {
			Try {
				# Attempt to ping the domain controller
				$result = Test-Connection -ComputerName $DC -Count 1 -ErrorAction Stop
				
				#count the number of enabled users in Active Directory on the Specific domain controllers
				$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $DC).Count
				
				[PSCustomObject]@{
					Server    = $using:DC
					Status    = 'Online'
					Response  = $result.ResponseTime
					UserCount = $usercount
				}
			} Catch {
				# Handle any errors, such as unreachable server
				[PSCustomObject]@{
					Server    = $using:DC
					Status    = 'Offline'
					Response  = 'N/A'
					UserCount = 'N/A'
				}
			}
		}
	}
}

Function Test-DomainControllersLINQ {
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5
	)
	
	# Create a synchronized collection to store results
	$results = [System.Collections.Concurrent.ConcurrentBag[pscustomobject]]::new()
	
	# Define the parallel options
	$parallelOptions = New-Object System.Threading.Tasks.ParallelOptions
	$parallelOptions.MaxDegreeOfParallelism = $ThrottleLimit
	
	# Use Parallel.ForEach to process each domain controller concurrently
	[System.Threading.Tasks.Parallel]::ForEach($DomainControllers, $parallelOptions, {
			Param ($DC)
			
			Try {
				# Attempt to ping the domain controller
				$result = Test-Connection -ComputerName $DC -Count 1 -ErrorAction Stop
				
				# Count the number of enabled users in Active Directory on the Specific domain controllers
				$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $DC).Count
				
				# Add result to the synchronized collection
				$results.Add([PSCustomObject]@{
						Server    = $DC
						Status    = 'Online'
						Response  = $result.ResponseTime
						UserCount = $usercount
					})
			} Catch {
				# Handle any errors, such as unreachable server
				$results.Add([PSCustomObject]@{
						Server    = $DC
						Status    = 'Offline'
						Response  = 'N/A'
						UserCount = 'N/A'
					})
			}
		})
	
	# Return all results
	$results
}

