## Add function to Get-Folder


Function CalculateFolderSize {
	Param
	(
		[Parameter(Mandatory = $true)]
		[string]$TargetFolder
	)
	
	$folderSize = (Get-ChildItem -Path $TargetFolder -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
	$folderSize = [math]::Round($folderSize, 2)
	Return $folderSize
}

Function Get-Folder($initialDirectory = "") {
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
	
	$foldername = New-Object System.Windows.Forms.FolderBrowserDialog
	$foldername.Description = "Select a folder"
	$foldername.rootfolder = "MyComputer"
	$foldername.SelectedPath = $initialDirectory
	
	If ($foldername.ShowDialog() -eq "OK") {
		$folder += $foldername.SelectedPath
	}
	Return $folder
}

##  Add variables
$folderpath = Get-Folder
$numberDaysOffset = Read-Host -Prompt 'Input the number of days of current data to retain'
$archiveDate = (Get-Date).AddDays(-$numberDaysOffset)

#DUPLICATION
$folderSize_Before = CalculateFolderSize -TargetFolder $folderpath

## does folder path exist
If (test-Path -Path $folderpath) {
	## write what will be done to screen
	Write-host "All files in the ", $folderpath " folder before ", $archiveDate, " will be deleted"
	Write-host "before deletion there is ", $folderSize_Before, " GB of data"

	## confirm if we want to proceed
	$confirmation = Read-Host "Are you Sure You Want To Proceed:"
	If ($confirmation -eq 'y') {
		## run the command to remove older files
		Get-ChildItem -Path $folderpath -Recurse | Where-Object { ($_.LastWriteTime -lt $archiveDate) } | Remove-Item
		
		## calculate remaining data and what was removed
		# DUPLICATION
		$folderSize_After = CalculateFolderSize -TargetFolder $folderpath
		$amountDeleted = $folderSize_Before - $folderSize_After
		
		## Display results
		Write-Output host
		Write-Output host "Total folder size in GB before deletion is -- ", $folderSize_Before, " GB"
		Write-Output host
		Write-Output host "Total folder size in GB after deletion is -- ", $folderSize_After, " GB"
		Write-Output host
		Write-Output host "Total amount of data removed in GB is -- ", $amountDeleted, " GB"
	} Else {
		"No action taken!"
		exit
	}
	
} Else {
	Write-Host "Folder does not exist. Please check the path and try again"
}