<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	6/29/2024 10:41 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	ParallelProcessingDemo.ps1
	===========================================================================
	.DESCRIPTION
		A comparison of regular ForEach-Object loop to workflows, runspace, jobs and powershell 7 ForEach-Object -Parallel
#>

Function Test-DomainControllersPS7 {
	<#
	.SYNOPSIS
	    Tests the connectivity and retrieves user counts from a list of domain controllers using PowerShell 7 parallel processing.

	.DESCRIPTION
	    This function pings each domain controller in the provided list and retrieves the count of enabled users 
	    from Active Directory. It uses the `ForEach-Object -Parallel` construct available in PowerShell 7 to perform 
	    these tasks concurrently, with a throttle limit to control the number of concurrent operations.

	    PowerShell 7 introduces significant improvements in parallel processing with the `ForEach-Object -Parallel` 
	    parameter. This feature allows script blocks to run in parallel threads, which improves performance by 
	    efficiently utilizing system resources. Unlike traditional background jobs, this method is more straightforward 
	    and integrates seamlessly into the pipeline, making the code cleaner and easier to manage. By using parallel 
	    processing, this function can test multiple domain controllers at the same time, significantly reducing the 
	    overall execution time.

	.PARAMETER DomainControllers
	    An array of domain controller names to test.

	.PARAMETER ThrottleLimit
	    The maximum number of concurrent operations. Defaults to 5.

	.EXAMPLE
	    Test-DomainControllersPS7 -DomainControllers @("DC1", "DC2") -ThrottleLimit 3

	.NOTES
	    This function requires PowerShell 7.0 or higher and the Active Directory module.
	    It will throw an error if executed on a lower version of PowerShell.

	#>
	
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
	} -ThrottleLimit $ThrottleLimit #Limit the parallelism using the -ThrottleLimit param
}

Function Test-DomainControllersRS {
	<#
	.SYNOPSIS
	    Tests the connectivity and retrieves user counts from a list of domain controllers.

	.DESCRIPTION
	    This function pings each domain controller in the provided list and retrieves the count of enabled users 
	    from Active Directory. It uses PowerShell runspaces to perform these tasks concurrently. 

	    A PowerShell runspace is an instance of the PowerShell runtime environment, which allows you to run commands 
	    and scripts. Runspaces are like lightweight threads that can be used to execute multiple tasks simultaneously 
	    without creating full PowerShell processes. This makes them more efficient for concurrent operations. 
	    By using runspaces, this function can test multiple domain controllers at the same time, improving performance 
	    and reducing the overall execution time.

	.PARAMETER DomainControllers
	    An array of domain controller names to test.

	.PARAMETER ThrottleLimit
	    The maximum number of concurrent operations. Defaults to 5.

	.EXAMPLE
	    Test-DomainControllersRS -DomainControllers @("DC1", "DC2") -ThrottleLimit 3

	.NOTES
	    This function requires the Active Directory module.

	#>
	
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5
	)
	
	# Create a runspace pool with a minimum of 1 and a maximum of ThrottleLimit runspaces
	$runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
	$runspacePool.Open()
	
	$runspaces = @()
	ForEach ($DC In $DomainControllers) {
		# Create a PowerShell instance and add a script to ping the domain controller and get user count
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
		
		# Assign the runspace pool to the PowerShell instance
		$powershell.RunspacePool = $runspacePool
		
		# Store the PowerShell instance and its async status in the runspaces array
		$runspaces += [PSCustomObject]@{
			Pipe   = $powershell
			Status = $powershell.BeginInvoke()
		}
	}
	
	# Process the results of each runspace
	ForEach ($runspace In $runspaces) {
		$runspace.Pipe.EndInvoke($runspace.Status)
		$runspace.Pipe.Dispose()
	}
	
	#Cleanup runspace allocation
	$runspacePool.Close()
	$runspacePool.Dispose()
	
	# Return any errors from the runspaces
	Return $runspaces.Pipe | ForEach-Object { $_.Streams.Error.ReadAll() }
}

Function Test-DomainControllersJob {
	<#
	.SYNOPSIS
	    Tests the connectivity and retrieves user counts from a list of domain controllers using PowerShell jobs.

	.DESCRIPTION
	    This function pings each domain controller in the provided list and retrieves the count of enabled users 
	    from Active Directory. It uses PowerShell jobs to perform these tasks concurrently, with a throttle limit 
	    to control the number of concurrent operations.

	    A PowerShell job is a background task that runs asynchronously. Jobs are useful for performing tasks 
	    that might take a long time to complete, without blocking the PowerShell session. Each job runs in its 
	    own environment, which means it does not interfere with other jobs or the main session. By using jobs, 
	    this function can test multiple domain controllers simultaneously, improving performance and reducing 
	    the overall execution time.

	.PARAMETER DomainControllers
	    An array of domain controller names to test.

	.PARAMETER ThrottleLimit
	    The maximum number of concurrent jobs. Defaults to 5.

	.EXAMPLE
	    Test-DomainControllersJob -DomainControllers @("DC1", "DC2") -ThrottleLimit 3

	.NOTES
	    This function requires the Active Directory module.

	#>
	
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
	<#
	.SYNOPSIS
	    Tests the connectivity and retrieves user counts from a list of domain controllers using a regular ForEach loop.

	.DESCRIPTION
	    This function pings each domain controller in the provided list and retrieves the count of enabled users 
	    from Active Directory. It processes each domain controller serially using a regular `ForEach` loop.

	    Using a regular `ForEach` loop processes each item one at a time in sequence. While this approach is simple 
	    and straightforward, it can be significantly slower compared to methods that use parallel processing. 
	    The main challenge with this approach is that it does not utilize system resources efficiently, especially 
	    when dealing with a large number of domain controllers or when network latency is high. Each operation waits 
	    for the previous one to complete before starting, which can result in longer overall execution times.

	    For scenarios requiring faster execution, consider using methods that support parallelism, such as 
	    `ForEach-Object -Parallel` in PowerShell 7 or runspaces and jobs in earlier versions of PowerShell. These 
	    methods can run multiple tasks concurrently, thus reducing the total time needed to process all items.

	.PARAMETER DomainControllers
	    An array of domain controller names to test.

	.EXAMPLE
	    Test-DomainControllers -DomainControllers @("DC1", "DC2")

	.NOTES
	    This function requires the Active Directory module.

	#>
	
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

Workflow Test-DomainControllersWF {
	<#
	.SYNOPSIS
	    Tests the connectivity and retrieves user counts from a list of domain controllers using a PowerShell Workflow.

	.DESCRIPTION
	    This function is implemented as a PowerShell Workflow to process domain controllers in parallel. 

	    A PowerShell Workflow is a sequence of activities that can be run sequentially or in parallel. Workflows are 
	    designed for long-running, repeatable tasks and can be suspended, resumed, and checkpointed. They are especially 
	    useful for managing state across restarts, handling complex automation scenarios, and running tasks on multiple 
	    machines concurrently. This function uses a workflow to take advantage of parallel execution, allowing multiple 
	    domain controllers to be processed simultaneously, which can significantly reduce the overall execution time.

	.PARAMETER DomainControllers
	    An array of domain controller names to test.

	.PARAMETER ThrottleLimit
	    The maximum number of concurrent operations. Defaults to 5.

	.EXAMPLE
	    Test-DomainControllersWF -DomainControllers @("DC1", "DC2") -ThrottleLimit 3

	.NOTES
	    This function requires the Active Directory module and is designed to run in a PowerShell Workflow context.
	    InlineScript is used to execute commands not natively supported by workflows.

	#>
	
	Param (
		[String[]]$DomainControllers,
		[int]$ThrottleLimit = 5
	)
	
	# Process each domain controller in parallel
	ForEach -ThrottleLimit $ThrottleLimit -Parallel ($DC In $DomainControllers) {
		# Use InlineScript to run commands that are not supported directly in workflows
		InlineScript {
			Try {
				# Attempt to ping the domain controller
				$result = Test-Connection -ComputerName $using:DC -Count 1 -ErrorAction Stop
				
				# Count the number of enabled users in Active Directory on the specific domain controller
				$usercount = (Get-ADUser -Filter 'Enabled -eq $true' -Server $using:DC).Count
				
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

Function Run-Test {
	<#
	.SYNOPSIS
	    Executes a specified function to test domain controllers and records the results.

	.DESCRIPTION
	    This function runs a specified test function on a list of domain controllers, measures the execution time, 
	    and exports the results to a specified directory. It also analyzes the results to count the number of offline 
	    domain controllers and those with valid user counts.

	.PARAMETER DCs
	    An array of domain controller names to test.

	.PARAMETER FunctionName
	    The name of the function to execute. This function should accept parameters -DomainControllers and -ThrottleLimit.

	.PARAMETER Throttle
	    The maximum number of concurrent operations. Defaults to 5.

	.PARAMETER ResultPath
	    The directory path where the results and error logs will be saved. Defaults to "C:\temp\SpeedTest".

	.EXAMPLE
	    Run-Test -DCs @("DC1", "DC2") -FunctionName "Test-DomainControllers" -Throttle 3 -ResultPath "C:\Results"

	.NOTES
	    This function requires the specified test function to be defined and should follow the parameter convention 
	    of accepting -DomainControllers and -ThrottleLimit.

	#>
	
	Param (
		[String[]]$DCs,
		[String]$FunctionName,
		[int]$Throttle = 5,
		[string]$ResultPath = "C:\temp\SpeedTest"
	)
	
	If (-Not (Test-Path $ResultPath)) { mkdir $ResultPath }
	
	$Error.Clear()
	
	# Measure the execution time
	$Timer = Measure-Command {
		$results = & $FunctionName -DomainControllers $DCs -ThrottleLimit $ThrottleLimit
	}
	
	$results | Export-Clixml -Path (Join-Path -Path $ResultPath -ChildPath "$($FunctionName)_$($ThrottleLimit).xml")
	
	# Analyze results
	$OfflineCount = ($results | Where-Object { $_.Status -eq 'Offline' } | Measure-Object).Count
	$ValidUserCounts = ($results | Where-Object { $_.UserCount -ne 'N/A' }).Count
	
	If ($null -eq $OfflineCount) { $OfflineCount = 0 }
	
	If ($Error.Count -gt 0) {
		$Error | Export-Clixml -Depth 99 -Path (Join-Path -Path $ResultPath -ChildPath "ERROR-$($FunctionName).xml")
	}
	
	# Convert execution time to hours, minutes, and seconds
	$ExecutionTimeSpan = [TimeSpan]::FromMilliseconds($Timer.TotalMilliseconds)
	$FormattedExecutionTime = "{0:hh\:mm\:ss}" -f $ExecutionTimeSpan
	
	# Output results
	[PSCustomObject]@{
		Function	    = $FunctionName
		DCCount	        = $DCs.count
		ThrottleLimit   = If ($Max) { "Max" } else { $Throttle }
		ExecutionTime   = $FormattedExecutionTime
		OfflineCount    = $OfflineCount
		ValidUserCounts = $ValidUserCounts
		ErrorCount      = $Error.Count
	}
}


#######################################
##           MAIN SCRIPT             ##
#######################################

# Setup Vars
$DomainControllers = Get-ADDomainController -Filter * # Get a list of Domain Controllers from the current domain.
$TestResults = @() # Create an empty array
$ResultPath = "C:\temp\SpeedTest" #Define results directory
$Batchsize = @(10, 20, 30, 40, 46) # Define batch sizes to run

#Test PS Version and set vars
If ($PSVersionTable.PSVersion.Major -lt 7) {
	$FunctionList = @('Test-DomainControllersRS', 'Test-DomainControllersWF', 'Test-DomainControllersJob')
	$ResultFileName = "Results_ps51.xml"
} Else {
	$FunctionList = @('Test-DomainControllersPS7')
	$ResultFileName = "Results_ps7.xml"
}

#Loop throught each function
ForEach ($F In $FunctionList) {
	#Loop through each batch size
	ForEach ($B in $Batchsize) {
		# Run tests with different throttle limits
		Write-Host "Running $F with a ThrottleLimit of $B"
		$TestResults += Run-Test -FunctionName $F -DCs $DomainControllers -Throttle $B
	}
}

# Display test results
$TestResults | Export-Clixml -Path (Join-Path -Path $ResultPath -ChildPath $ResultFileName)


