# Enable long path support in PowerShell and Windows
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1

##### Define the folder path and server name #####
#### Specify your folder path here ####
$folderPath = "\\Sourceserver\folderpath"      
$serverName = $env:COMPUTERNAME                # Automatically get current server name

# Extract folder name (last part of the folder path)
$folderName = Split-Path $folderPath -Leaf

# Generate timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

# Combine into output file name
$outputCsv = ".\${serverName}-${folderName}-PermissionsReport-${timestamp}.csv"

$skippedFoldersCsv = ".\SkippedFolders.csv"  # CSV file for skipped folders

# Initialize CSV files with headers
$headers = "ServerName,Permissions,IdentityReference,IsInherited,ShareName,LastWriteTime,AccessControlType,FolderPath"
Set-Content -Path $outputCsv -Value $headers

$skippedHeaders = "FolderPath,Reason"
Set-Content -Path $skippedFoldersCsv -Value $skippedHeaders

# Function to safely get ACL with error handling and log skipped folders
function Get-SafeAcl {
    param([string]$path)
    try {
        return Get-Acl -LiteralPath $path
    }
    catch {
        Write-Warning "Could not get ACL for: $path"
        # Log skipped folder to separate CSV
        $skipRow = [PSCustomObject]@{
            FolderPath = $path
            Reason     = "Could not retrieve ACL"
        }
        $skipRow | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -Path $skippedFoldersCsv
        return $null
    }
}

# Function to convert ACL permissions to comparable string
function Convert-PermissionsToString {
    param([System.Security.AccessControl.AuthorizationRuleCollection]$access)
    
    $permList = foreach ($rule in $access) {
        # Only include explicit (non-inherited) permissions
        if (-not $rule.IsInherited) {
            "{0}|{1}|{2}" -f $rule.IdentityReference, 
                           $rule.FileSystemRights, 
                           $rule.AccessControlType
        }
    }
    return ($permList | Sort-Object) -join ";"
}

# Function to get parent folder's ACL
function Get-ParentAcl {
    param([string]$path)
    
    $parentPath = Split-Path -Path $path -Parent
    if ($parentPath) {
        return Get-SafeAcl $parentPath
    }
    return $null
}

# Initialize counter for processed items
$processedCount = 0
$uniqueCount = 0

try {
    Write-Host "Starting to process folder: $folderPath"
    
    # Ensure the path exists
    if (-not (Test-Path -LiteralPath $folderPath)) {
        throw "The specified path does not exist: $folderPath"
    }

    # Process root folder first
    $rootAcl = Get-SafeAcl $folderPath
    if ($rootAcl) {
        try {
            $rootLastWriteTime = (Get-Item -LiteralPath $folderPath -Force).LastWriteTime
        }
        catch {
            $rootLastWriteTime = $null
            Write-Warning "Could not get last write time for root folder: $folderPath"
        }
        
        # Root folder permissions are always exported if explicit
        foreach ($access in $rootAcl.Access) {
            if (-not $access.IsInherited) {
                $row = [PSCustomObject]@{
                    ServerName         = $serverName
                    Permissions        = $access.FileSystemRights
                    IdentityReference  = $access.IdentityReference
                    IsInherited        = $access.IsInherited
                    ShareName          = Split-Path $folderPath -Leaf
                    LastWriteTime      = $rootLastWriteTime
                    AccessControlType  = $access.AccessControlType
                    FolderPath         = $folderPath
                }
                $row | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -Path $outputCsv
                $processedCount++
                $uniqueCount++
            }
        }
    }

    # Process all subfolders
    Get-ChildItem -LiteralPath $folderPath -Directory -Recurse -Force -ErrorAction Continue | ForEach-Object {
        $folder = $_
        Write-Host "Processing folder: $($folder.FullName)" -ForegroundColor Green
        
        $currentAcl = Get-SafeAcl $folder.FullName
        if (-not $currentAcl) {
            return  # Skip processing if ACL retrieval failed
        }

        $parentAcl = Get-ParentAcl $folder.FullName
        $currentPermissions = Convert-PermissionsToString $currentAcl.Access
        $parentPermissions = if ($parentAcl) { Convert-PermissionsToString $parentAcl.Access } else { "" }
        
        # Only process if permissions are different from parent and not inherited
        if ($currentPermissions -ne $parentPermissions) {
            try {
                $lastWriteTime = (Get-Item -LiteralPath $folder.FullName -Force).LastWriteTime
            }
            catch {
                $lastWriteTime = $null
                Write-Warning "Could not get last write time for: $($folder.FullName)"
                # Log the folder to skipped CSV with reason
                $skipRow = [PSCustomObject]@{
                    FolderPath = $folder.FullName
                    Reason     = "Could not get last write time"
                }
                $skipRow | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -Path $skippedFoldersCsv
                return
            }
            
            foreach ($access in $currentAcl.Access) {
                if (-not $access.IsInherited) {
                    $row = [PSCustomObject]@{
                        ServerName         = $serverName
                        Permissions        = $access.FileSystemRights
                        IdentityReference  = $access.IdentityReference
                        IsInherited        = $access.IsInherited
                        ShareName          = Split-Path $folderPath -Leaf
                        LastWriteTime      = $lastWriteTime
                        AccessControlType  = $access.AccessControlType
                        FolderPath         = $folder.FullName
                    }
                    $row | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -Path $outputCsv
                    $uniqueCount++
                }
            }
        }
        $processedCount++
    }

    Write-Host "Processing complete!" -ForegroundColor Green
    Write-Host "Total folders processed: $processedCount" -ForegroundColor Green
    Write-Host "Folders with unique permissions: $uniqueCount" -ForegroundColor Green
    Write-Host "Report saved to: $outputCsv" -ForegroundColor Green
    Write-Host "Skipped folders logged to: $skippedFoldersCsv" -ForegroundColor Green
}
catch {
    Write-Error "An error occurred while processing the folders: $_"
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Folders processed before error: $processedCount" -ForegroundColor Yellow
    Write-Host "Unique permissions found before error: $uniqueCount" -ForegroundColor Yellow
}
