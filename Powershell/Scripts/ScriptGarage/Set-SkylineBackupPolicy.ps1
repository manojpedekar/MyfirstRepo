<#
    .SYNOPSIS
        Sets backupPolicy on a list of cloud instances from a CSV. Despite
        the original filename PowerOnSSCCLient01.ps1, this script does NOT
        power on anything - it updates backup policy on Skyline/SSCClient01
        servers.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed circa 2023-2024 to set
        the backup policy on the Skyline-hosted SS&C Client01 instances. Two
        flows in this file:

          1. YKTSkylineServers.csv: per-instance assignment of backupPolicy
             "YKT-VM-MONTH-3-10PM-RP" with throttling between API calls.
          2. KCSkylineServers: bulk assignment of "WDC-VM-Month-3-10PM-RP"
             to all KC instances under a hardcoded projectId, where
             backupPolicy is currently unset.

        Helper functions (Start-Countdown, Get-CloudInstanceDetails,
        Set-CloudInstance) are preserved inline as the historical record
        of what was actually executed. Canonical versions now live in:
          - Start-Countdown -> Powershell/Functions/Start-Countdown.ps1
          - Get-CloudInstanceDetails -> Cloud-API Get-Instance -instanceId
          - Set-CloudInstance -> Cloud-API Set-Instance

        Do not re-run without reviewing the hardcoded projectId, the YKT/KC
        backup policy names, and confirming the rate-limit timing is still
        appropriate.
#>

Function Start-Countdown {
	Param (
		[int]$Minutes = 5,
		[string]$ProgressBarName = "Countdown"
	)
	
	# Convert minutes to seconds
	$totalSeconds = $Minutes * 60
	$originalSeconds = $totalSeconds
	
	While ($totalSeconds -gt 0) {
		# Calculate the percentage remaining (for countdown effect)
		$percentComplete = ($totalSeconds / $originalSeconds) * 100
		
		# Update the progress bar
		Write-Progress -Id 1 -Activity $ProgressBarName -Status "$totalSeconds seconds remaining" -PercentComplete $percentComplete
		
		# Wait for one second
		Start-Sleep -Seconds 1
		
		# Decrement the total time left
		$totalSeconds--
	}
	
	# Complete the progress bar
	Write-Progress -Id 1 -Activity $ProgressBarName -Completed
}


Function Get-CloudInstanceDetails {
	Param
	(
		[ValidateNotNullOrEmpty()]
		[string]$APIKey,
		[string]$MachineId
	)
	
	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$headers.Add("x-api-key", $APIKey)
	$headers.Add("Content-Type", "application/json")
	
	$request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$MachineId"
	
	$response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
	
	Return $response.content
}

Function Set-CloudInstance {
	Param
	(
		[ValidateNotNullOrEmpty()]
		[string]$APIKey,
		[Parameter(Mandatory = $true)]
		[string]$MachineId,
		[string]$body
	)
	
	#TODO: Place script here
	
	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$headers.Add("x-api-key", $APIKey)
	$headers.Add("Content-Type", "application/json")
	
	$request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$MachineId"
	
	$response = Invoke-RestMethod $request -Method 'PUT' -Headers $headers -Body $body
	
	Return $response.content
}



$APIKEY = ""

$headers = @{
	"accept"    = "application/json"
	"x-api-key" = $APIKEY
}

$YKTSkylineServers = import-csv .\YKTSkylineData.csv | select *, Results, Request


$total = $YKTSkylineServers.Count
$i = 0
$c = 0

$YKTSkylineServers | ForEach-Object {
	$update = $false
	$i++
	$percentComplete = ($i / $total) * 100
	Write-Host "Starting $($_.Assignmnet) -- $($_.CloudID)"
	$statusMessage = "Processing instance $($_.CloudID) -- Customer = $($_.Assignmnet) -- ($i of $total)"
	Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Getting Cloud Data"
	
	# Get the current cloud instance details
	$CloudInstance = Get-CloudInstanceDetails -APIKey $APIKey -MachineId $_.CloudID
	
	Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Assembling Data"
	# Create the json request
	$body = [PSCustomObject]@{
		name = $CloudInstance.name
		size = $CloudInstance.size
		patchingGroup = "YKT-VM-MONTH-3-10PM-RP"
		markAsEnterpriseDatabase = $false
		markAsEnterpriseCluster = $false
	}
	
	# Check if $CloudInstance.backupPolicy has a value
	If (![string]::IsNullOrEmpty($CloudInstance.backupPolicy)) {
		$body | Add-Member -MemberType NoteProperty -Name "backupPolicy" -Value $CloudInstance.BakupPolicy
		Write-Host "  -- Backup Policy already set to $($CloudInstance.backupPolicy)" -ForegroundColor Green
		$update = $false
	} Else {
		Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Adding Backup Policy"
		$body | Add-Member -MemberType NoteProperty -Name "backupPolicy" -Value $_.BakupPolicy
		Write-Host "  -- Backup Policy requires update" -ForegroundColor Yellow
		$update = $True
	}
	
	If ($Update) {
		$c++
		$body = $body | ConvertTo-Json
		
		$_.Request = $body
		Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Setting Cloud Data"
		$_.results = Set-CloudInstance -APIKey $APIKey -MachineId $_.CloudID -body $body
		Write-Host "  -- Update complete"
	} Else {
		Write-Host "  -- Instance not updated"
	}
	
	
	# Add a wait every 5 loops
	If ($c % 5 -eq 0 -and $c -ne 0) {
		Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Waiting"
		Start-Countdown -Minutes 4 -ProgressBarName "Time before next API call"
	}
}























































$InstanceIDs = Get-CloudInstances -APIKey $APIKEY -projectId project-de361c84-3fee-491f-afe2-761bd6642dd6

$allSkylineServers = $InstanceIDs | ForEach-Object { Get-CloudInstanceDetails -APIKey $APIKey -MachineId $_.id | Select-Object id, name, backupPolicy, site, dns, size, patchingGroup }

$KCSkylineServers = $allSkylineServers | Where-Object { $_.backupPolicy -eq $null -and $_.name -notlike "Test*" -and $_.site -eq "na-central-kc"} | Select-Object *, Results, Request

$total = $KCSkylineServers.Count
$i = 0
$c = 0

$KCSkylineServers | ForEach-Object {
	$i++
	$percentComplete = ($i / $total) * 100
	Write-Host "Starting $($_.name) -- $($_.id)"
	$statusMessage = "Processing instance $($_.id) -- Customer = $($_.name) -- ($i of $total)"
	
	Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Assembling Data"
	# Create the json request
	$body = [PSCustomObject]@{
		name = $_.name
		size = $_.size
		patchingGroup = $_.patchingGroup
		backupPolicy = "WDC-VM-Month-3-10PM-RP"
		markAsEnterpriseDatabase = $false
		markAsEnterpriseCluster = $false
	}
	
	$body = $body | ConvertTo-Json
	
	$_.Request = $body
	Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Setting Cloud Data"
	$_.results = Set-CloudInstance -APIKey $APIKey -MachineId $_.id -body $body
	Write-Host "  -- Update complete"
	
	Write-Progress -Activity "Updating Instances" -Status $statusMessage -PercentComplete $percentComplete -CurrentOperation "Waiting"
	Start-Countdown -Minutes 5 -ProgressBarName "Time before next API call"
}