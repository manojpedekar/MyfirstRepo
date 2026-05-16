# Import data from CSV
$data = Import-Csv .\InventoryScript.csv

# Initialize an array to store results
$results = @()

# Loop through each entry in the CSV
foreach ($entry in $data) {
    $IdentityReference = $entry.IdentityReference
    $FolderPath = $entry.FolderPath
    $Permissions = $entry.Permissions

    # Create folder if it doesn't exist
    if (-not (Test-Path $FolderPath)) {
        New-Item -ItemType Directory -Path $FolderPath | Out-Null
        Write-Host "Folder created: $FolderPath"
    }

    # Set permissions for the folder
    try {
        $acl = Get-Acl $FolderPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$IdentityReference", "$Permissions", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $FolderPath $acl
        Write-Host "Permissions applied for $IdentityReference on $FolderPath"
        $Permissions_Applied = "Successful"
    } catch {
        Write-Host "Failed to apply permissions for $IdentityReference on $FolderPath"
        $Permissions_Applied = "Failed"
    }

    # Add result to results array
    $results += [PSCustomObject]@{
        Server_Name = $env:COMPUTERNAME
        IdentityReference = $IdentityReference
        FolderPath = $FolderPath
        Permissions = $Permissions
        Permissions_Applied = $Permissions_Applied
    }
}

# Export results to CSV
$results | Export-Csv -Path .\Output-Build_Folders.csv -NoTypeInformation
