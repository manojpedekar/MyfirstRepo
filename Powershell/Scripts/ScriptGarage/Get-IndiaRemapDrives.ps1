<#
    .SYNOPSIS
        Scrapes 'remapdrives.cmd' files from every user home directory
        under the Airoli and Malad Mum fileservers, deduplicates the lines,
        normalizes them, and writes the unique UNC paths to C:\temp\AllUNCs.txt.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed 2024-01-30 to
        inventory the universe of mapped-drive UNC paths used across all
        India user profiles. Output (~234 unique UNCs after dedup +
        normalization) drove the share rationalization that followed.

        Hardcoded set of 11 D:\Airoli\... and D:\Malad\... HomeRoot paths.
        For each home folder under those roots, reads remapdrives.cmd and
        accumulates non-Z:-mapped lines. Final output goes to a fixed
        C:\temp\AllUNCs.txt path.

        Do not re-run without confirming the HomeRoots list is still
        accurate and that C:\temp\AllUNCs.txt is the desired output.
#>

$HomeRoots = @(
	'D:\Airoli\Mum1flsprd2\Home2',
	'D:\Airoli\Mum4flsprd1\home1',
	'D:\Airoli\Mum4flsprd1\home2',
	'D:\Airoli\Mum4flsprd2\Home3',
	'D:\Airoli\Mum4flsprd2\Home4',
	'D:\Airoli\Mum4flsprd3\Home5',
	'D:\Airoli\Mum4flsprd3\Home6',
	'D:\Malad\Mum2flsprd2\Home2',
	'D:\Malad\Mum2flsprd4\Home4',
	'D:\Malad\Mum2flsprd5\Home5',
	'D:\Malad\Mum2flsprd6\Home6'	
)

$AllDriveMappings = @()
$filecount = 0
$foldercount = 0

foreach ($HomeRoot in $HomeRoots) {
	$DIRList = Get-ChildItem -Path $HomeRoot -Directory
	
	ForEach ($HomeDir In $DIRList){
		$foldercount++
		If ((Test-Path "$($HomeDir.FullName)\remapdrives.cmd")) {
			$filecount++
			$AllDriveMappings += Get-Content "$($HomeDir.FullName)\remapdrives.cmd" | Where-Object { $_ -notlike "net use Z: *" }
		}
	}
}

# 10,703 lines
$AllDriveMappings | Measure-Object


# 306 Lines
$AllDriveMappings | Select-Object -Unique | Measure-Object


# 234 Lines
($AllDriveMappings | Select-Object -Unique).replace(" /PERSISTENT:YES", "").replace("net use ", "") | ForEach-Object { $_.substring(3, ($_.length) - 3) } | Select-Object -unique | Out-File C:\temp\AllUNCs.txt


# 3,652 folders  --- 2,480 Files