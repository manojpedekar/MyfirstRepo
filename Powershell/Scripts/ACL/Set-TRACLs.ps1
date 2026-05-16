

Function DuplicateAceWithNewGroup {
	Param (
		[Parameter(Mandatory = $true)]
		[System.Security.AccessControl.FileSystemAccessRule]$Ace,
		[Parameter(Mandatory = $true)]
		[string]$LocalGroupName
	)
	
	# Create a new ACE object with the same properties as the original, but with a different IdentityReference
	$newAce = New-Object System.Security.AccessControl.FileSystemAccessRule(
		$LocalGroupName,
		$Ace.FileSystemRights,
		$Ace.InheritanceFlags,
		$Ace.PropagationFlags,
		$Ace.AccessControlType
	)
	
	# Return the new ACE
	Return $newAce
}

Function Test-LocalGroupExists {
	Param (
		[Parameter(Mandatory = $true)]
		[string]$GroupName
	)
	
	Try {
		$group = Get-LocalGroup -Name $GroupName -ErrorAction Stop
		Return $true
	} Catch {
		# If an error occurs (group not found), return false
		Return $false
	}
}


Function Get-AclsWithSid {
	Param (
		[Parameter(Mandatory = $true)]
		[string]$FolderPath
	)
	
	# Check if the folder exists
	If (-not (Test-Path $FolderPath)) {
		Write-Error "Folder path not found: $FolderPath"
		Return
	}
	
	# Import data from XML
	$importedData = Import-Clixml c:\temp\localGroups.xml
	
	# Initialize an empty hash table for old group SIDs
	$oldgroupsHashTable = @{ }
	ForEach ($item In $importedData) {
		$oldgroupsHashTable[$item.OldSid] = @{
			GroupName = $item.GroupName
			OldSid    = $item.OldSid
		}
	}
	
	# Get all directories including the root
	Write-Progress -Activity "Collecting a list of directories to process ..." 
	$directories = Get-ChildItem -Path $FolderPath -Recurse -Directory -Force -ErrorAction SilentlyContinue
	$directories += Get-Item -Path $FolderPath
	
	# Count total directories for the progress bar
	$totalDirectories = $directories.Count
	$currentDirectoryIndex = 0
	
	# Loop through each directory and get ACLs
	ForEach ($dir In $directories) {
		# Increment the current directory index for the progress bar
		$currentDirectoryIndex++
		# Display the progress bar
		$percentComplete = ($currentDirectoryIndex / $totalDirectories) * 100
		Write-Progress -Activity "Processing Directories ($currentDirectoryIndex of $totalDirectories)" -Status "$($dir.FullName)" -PercentComplete $percentComplete
		
		$changes = $false
		Try {
			$acls = Get-Acl -Path $dir.FullName
			
			# Process each ACL entry for directory
			ForEach ($ace In $acls.Access) {
				If ($ace.IdentityReference -is [System.Security.Principal.SecurityIdentifier] -and $ace.IsInherited -eq $false) {
					$sidGroupName = $oldgroupsHashTable[$ace.IdentityReference.value].GroupName
					
					$LocalGroupExists = Test-LocalGroupExists -GroupName $sidGroupName
					
					If ($LocalGroupExists) {
						$updatedACE = DuplicateAceWithNewGroup -LocalGroupName "$env:COMPUTERNAME\$sidGroupName" -Ace $ace
						
						$acls.AddAccessRule($updatedACE) | Out-Null
						$acls.RemoveAccessRule($ace) | Out-Null
						$changes = $true
					} Else {
						Write-Host "Group with SID $($ace.IdentityReference.value) not found for folder $($dir.FullName)." -ForegroundColor Red
					}
				}
			}
			
			# Update ACLs only if changes were made
			If ($changes) {
				Set-Acl -Path $dir.FullName -AclObject $acls
				Write-Host "ACLs updated for directory: $($dir.FullName)" -ForegroundColor Green
			}
		} Catch {
			Write-Error "Error processing directory $($dir.FullName): $_"
		}
	}
	# End of progress bar when the loop is complete
	Write-Progress -Activity "Processing Directories" -Completed
}


Get-AclsWithSid -FolderPath R:\tr