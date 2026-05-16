<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/13/2022 8:46 AM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


$FileName = "C:\temp\patchresults.txt"
(Get-Content $FileName).replace(" Server: ", "").replace("Status: ", "").replace("OS:", "") | ConvertFrom-Csv -Header Server, Status, OS | select *, @{ N = "Domain"; e = { $_.Server.Substring($_.Server.IndexOf(".") + 1, $_.Server.Length - $_.Server.IndexOf(".") - 1)} }