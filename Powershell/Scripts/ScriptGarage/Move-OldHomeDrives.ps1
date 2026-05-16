<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/11/2022 12:47 PM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



#$NewFolder = "$NewRoot\$(Split-Path $_ -Leaf)"

$NewRoot = "L:\OLD_HomeDirs\20221111"
$DisableUsers = Get-Content C:\temp\OldHomeDrives9.txt
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:c:\temp\move8\$(Split-Path $_ -Leaf).log }

$NewRoot = "T:\TERMED_Homedirs\20221111"
$DisableUsers = Get-Content C:\temp\OldHomeDrives10.txt
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:c:\temp\BigMove\$(Split-Path $_ -Leaf).log }


function clean-oldshares
{
	$SharesToRemove = @()
	Get-SmbShare | ? { $_.path -like "*home*" } | % { if (-not (Test-Path $_.path)) { $SharesToRemove += $_ } }
	
	$i = 0
	$TotalItems = $SharesToRemove.count
	
	foreach ($ShareToRemove in $SharesToRemove)
	{
		$i++
		Write-Progress -Activity "Removing $($ShareToRemove.name)" -PercentComplete ($i / $TotalItems * 100) -Status "Line $i of $TotalItems"
		Remove-SmbShare -Name $ShareToRemove.name -force
	}
}



$NewRoot = "L:\OLD_HomeDirs\20221111"
"E:\homedirs\TERMED_dt111797" | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:$(Split-Path $_ -Leaf).log }
"E:\homedirs\DT215217ADM" | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:Robocopy.log }
Test-Path "E:\homedirs\DT215217ADM"
Test-Path "L:\OLD_HomeDirs\20221111\DT215217ADM"
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:Robocopy.log }
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:Robocopy.log }
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:Robocopy.log }
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:Robocopy.log }
$DisableUsers | % { robocopy $_ "$NewRoot\$(Split-Path $_ -Leaf)" /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /TEE /MOVE /LOG:Robocopy.log }


robocopy G:\homedirs2 E:\homedirs2 /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /mir; robocopy K:\homedirs3 E:\homedirs3 /E /ZB /DCOPY:T /COPYALL /R:1 /W:1 /V /mir