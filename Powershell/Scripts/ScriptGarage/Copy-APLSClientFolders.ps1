<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	1/20/2023 12:34 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

$Folders = @('00213000'
	 ,'10552000'
	 ,'10951000'
	 ,'10879000'
	 ,'10870000'
	 ,'10871000'
	 ,'10873000'
	 ,'10965000'
	 ,'10684000'
	 ,'10897000'
	 ,'10896000'
	 ,'11029000'
	 ,'10958000'
	 ,'11070000'
	 ,'10918000'
	 ,'95118000'
	 ,'11011000'
	 ,'11010000'
	 ,'10860000'
	 ,'10816000'
	 ,'24777000'
	 ,'11054000'
	 ,'83116000'
	 ,'10760000'
	 ,'10944000'
	 ,'28080000'
	 ,'87205000'
	 ,'89390000'
	 ,'15384000'
	 ,'80494000'
	 ,'57279000'
	 ,'61326000'
	 ,'47511000'
	 ,'10654000'
	 ,'10762000'
	 ,'10814000'
	 ,'10900000'
	 ,'74894000'
	 ,'72604000'
	 ,'60217000'
	 ,'26506000'
	 ,'58446000'
	 ,'60920000'
	 ,'10657000'
	 ,'10761000'
	 ,'10815000'
	 ,'10901000'
	 ,'33071000'
	 ,'83849000'
	 ,'86742000'
	 ,'39139000'
	 ,'10730000'
	 ,'00183000'
	 ,'00184000'
	 ,'00389000'
	 ,'00390000'
	 ,'00185000'
	 ,'00186000'
	 ,'00379000'
	 ,'38226000')

#$Folders = @('00213000', '10552000')

# Source Server is to \\wnpfsalpdatas03.dstcorp.net

$TARGET_FOLDER = "\\YKT2.isilon.ssnc.global\ifs\Hybrid\Clients\PEI\Cranford\Group\partnerships\ALPS_TXN"
#$TARGET_FOLDER = "G:\Test_Dest"
$LOG_FOLDER = "G:\Robocopy_Logs"

ForEach ($Folder In $Folders) {
	$SourceFolder = "F:\DATA\SYS1\krfs\$Folder"
	$TimeStamp = (get-date -Format ddMMyyhhmmss)
	$LogFile = "$LOG_FOLDER\$($Folder)_$($TimeStamp).log"
	If (test-path $SourceFolder ) {
		Robocopy $SourceFolder $TARGET_FOLDER\$folder /e /s /zb /copy:DATO /xo /r:1 /w:1 /log:$LogFile
	}Else {
		Write-Host "Source Folder not found -- $SourceFolder" -ForegroundColor Red
	}
	
}


Get-ChildItem -Recurse  | measure-object -property length -average

Set-Location F:\DATA\SYS1\krfs\


$FolderStats = @()
ForEach ($Folder  In $Folders) {
	$SourceFolder = "F:\DATA\SYS1\krfs\$Folder"
	$Results = Get-ChildItem $SourceFolder -Recurse | Measure-Object -Property length -Average -Sum -Maximum -Minimum
	
	$Average   = $Results.Average /1kb
	$TotalSize = $Results.Count
	$Maximum   = $Results.Maximum
	$Minimum      = $Results.Minimum
	
	$null = $FolderStats += ([PSCustomObject]@{
			Folder    = $Folder
			FileCount = $Results.Count
			Average   = $Results.Average /1kb
			TotalSize = $Results.sum /1mb
			Maximum   = $Results.Maximum /1kb
			Minimum      = $Results.Minimum /1kb
		})
	}
$FolderStats | Format-Table

mkdir c:\temp\Test512k
mkdir c:\temp\Test1m
mkdir c:\temp\Test10m
mkdir c:\temp\Test100m
mkdir c:\temp\Test1G
#512KB file
1 .. 2000 | ForEach-Object { fsutil file createnew c:\temp\Test512k\myfile$_.txt 524288 }
#1MB file
1..1000 | ForEach-Object { fsutil file createnew c:\temp\Test1m\myfile$_.txt 1048576 }
#10 MB file
1 .. 100 | ForEach-Object { fsutil file createnew c:\temp\Test10m\myfile$_.txt 10485760 }
#100 MB File
1 .. 10 | ForEach-Object { fsutil file createnew c:\temp\Test100m\myfile$_.txt 104857600 }
#1GB MB File
fsutil file createnew c:\temp\Test1g\myfile$_.txt 1048576000



$LogFile = "c:\temp\CopyTestLogs"
$TARGET_FOLDER = "\\YKT2.isilon.ssnc.global\ifs\Hybrid\Clients\PEI\Cranford\Group\partnerships\ALPS_TXN\NetworkCopyTest"
Robocopy c:\temp\Test1G $TARGET_FOLDER\Test1G /e /s /zb /copy:DATO /xo /r:1 /w:1 /log:$LogFile\Test1G.log
Robocopy c:\temp\Test100m $TARGET_FOLDER\Test100m /e /s /zb /copy:DATO /xo /r:1 /w:1 /log:$LogFile\Test100m.log
Robocopy c:\temp\Test10m $TARGET_FOLDER\Test10m /e /s /zb /copy:DATO /xo /r:1 /w:1 /log:$LogFile\Test10m.log
Robocopy c:\temp\Test1m $TARGET_FOLDER\Test1m /e /s /zb /copy:DATO /xo /r:1 /w:1 /log:$LogFile\Test1m.log

Robocopy c:\temp\Test512k $TARGET_FOLDER\Test512k /e /s /zb /copy:DATO /xo /r:1 /w:1 /log:$LogFile\Test512k.log
