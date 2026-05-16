Param
(
	[Parameter(Mandatory = $true,
			   HelpMessage = 'Specify the path to write the test file')]
	[string]$DestFolder = "C:\temp",
	[int]$durationSeconds = 60,
	[int]$sampleIntervalSeconds = 1
)

##########################################
###             FUNCTIONS              ###
##########################################

Function New-RandomFileName {
	Param (
		[string]$Path,
		[string]$Extension = "bin"
	)
	
	$randomFileName = [System.IO.Path]::GetRandomFileName()
	$randomFileName = [System.IO.Path]::ChangeExtension($randomFileName, $Extension)
	$fullPath = [System.IO.Path]::Combine($Path, $randomFileName)
	
	Return $fullPath
}

##########################################
###            MAIN SCRIPT             ###
##########################################

# Define the counter path for disk queue length; adjust as needed
$counterPath = "\PhysicalDisk(_Total)\Current Disk Queue Length"

$filePath = New-RandomFileName -Path $DestFolder

# Desired file size (10GB)
$fileSize = 10GB

# Block size for each write operation (1MB)
$blockSize = 1MB

$writeDurations = New-Object System.Collections.Generic.List[System.TimeSpan]

# Start disk queue length measurement in a background job
$diskQueueJob = Start-Job -ScriptBlock {
	Param ($sampleIntervalSeconds,
		$durationSeconds)
	
	# Use a more universally available counter, adjust as necessary
	$counterPath = "\PhysicalDisk(*)\Avg. Disk Queue Length"
	
	Try {
		$diskQueueLengthSamples = Get-Counter -Counter $counterPath -SampleInterval $sampleIntervalSeconds -MaxSamples ($durationSeconds / $sampleIntervalSeconds)
		$queueLengthValues = $diskQueueLengthSamples.CounterSamples | Select-Object -ExpandProperty CookedValue
		
		$minQueueLength = [math]::Round(($queueLengthValues | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum), 4)
		$maxQueueLength = [math]::Round(($queueLengthValues | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum), 4)
		$averageQueueLength = [math]::Round(($queueLengthValues | Measure-Object -Average | Select-Object -ExpandProperty Average), 4)
		
		Write-Output "Minimum Disk Queue Length: $minQueueLength"
		Write-Output "Maximum Disk Queue Length: $maxQueueLength"
		Write-Output "Average Disk Queue Length: $averageQueueLength"
	} Catch {
		Write-Error "Failed to retrieve disk queue length. Error: $_"
	}
} -ArgumentList $sampleIntervalSeconds, $durationSeconds


$FileCreationTime = Measure-Command {
	
	$block = New-Object byte[] $blockSize
	$random = New-Object System.Random
	$random.NextBytes($block)
	
	$stream = [System.IO.File]::OpenWrite($filePath)
	
	$bytesWritten = 0
	$totalBlocks = $fileSize / $blockSize
	
	While ($bytesWritten -lt $fileSize) {
		$startWriteTime = Get-Date
		$stream.Write($block, 0, $block.Length)
		$endWriteTime = Get-Date
		$writeDuration = $endWriteTime - $startWriteTime
		$writeDurations.Add($writeDuration)
		$bytesWritten += $blockSize
		
		$percentComplete = [math]::Round(($bytesWritten / $fileSize) * 100, 2)
		Write-Progress -PercentComplete $percentComplete -Status "Writing" -Activity "Writing to $($filePath): $percentComplete%"
	}
	
	$stream.Close()
	
}

Write-Host " "
Write-Host "Test Results for $($ENV:COMPUTERNAME)"
Write-Host "Time to create File:"

$FileCreationTime

# stop the job if it's still running
Stop-Job -Job $diskQueueJob

Wait-Job -Job $diskQueueJob | Out-Null
$diskQueueResults = Receive-Job -Job $diskQueueJob
Remove-Job -Job $diskQueueJob

# Display disk queue length results
$diskQueueResults | ForEach-Object { Write-Output $_ }

# Convert TimeSpan objects to total milliseconds for each write operation
$writeMilliseconds = $writeDurations | ForEach-Object { $_.TotalMilliseconds }

# Calculate average write duration in milliseconds
$averageWriteDurationMs = ($writeMilliseconds | Measure-Object -Average).Average

# Calculate average write speed in MB/s
$averageSpeedMBs = [math]::Round(($blockSize / 1MB) / ($averageWriteDurationMs / 1000), 2)

Write-Output "Average write speed: $($averageSpeedMBs) MB/s."

Write-Progress -PercentComplete $percentComplete -Status "Clean Up" -Activity "Deleting Temp File $($filePath): $percentComplete%"
Remove-Item $filePath
