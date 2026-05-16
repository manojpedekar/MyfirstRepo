# Import folder paths from CSV
$folderPaths = Import-Csv .\folder_paths.csv | Select-Object -ExpandProperty Folder_Paths

foreach ($path in $folderPaths) {
    Write-Host "Processing: ${path}" -ForegroundColor Yellow
    
    # Get current ACL
    $acl = Get-Acl $path
    
    # Store existing permissions before making changes
    $existingPermissions = $acl.Access | Where-Object {
        $_.IdentityReference -notlike "NT AUTHORITY\*" -and 
        $_.IdentityReference -notlike "BUILTIN\*" -and
        $_.IdentityReference -notlike "CREATOR OWNER"
    }

    # Create empty array for new permissions
    $newPermissions = @()
    
    # Display current permissions and store for modification
    Write-Host "Current permissions found:" -ForegroundColor Cyan
    foreach ($perm in $existingPermissions) {
        Write-Host "Identity: $($perm.IdentityReference)" -ForegroundColor Magenta
        
        # Create new read-only permission for each existing user/group
        $newRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $perm.IdentityReference,
            "ReadAndExecute",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $newPermissions += $newRule
    }

    # Prompt for confirmation
    $confirmation = Read-Host "Do you want to proceed with setting read-only permissions for ${path}? (y/n)"
    if ($confirmation -ne 'y') {
        Write-Host "Skipping: ${path}" -ForegroundColor Red
        continue
    }
    
    # Create new ACL
    $newAcl = New-Object System.Security.AccessControl.DirectorySecurity
    $newAcl.SetAccessRuleProtection($true, $false)
    
    # Add new read-only permissions
    foreach ($rule in $newPermissions) {
        $newAcl.AddAccessRule($rule)
    }
    
    # Add System and Administrators with full control
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM",
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $newAcl.AddAccessRule($adminRule)
    $newAcl.AddAccessRule($systemRule)

    try {
        # Apply the new ACL
        Set-Acl -Path $path -AclObject $newAcl
        Write-Host "Permissions successfully updated for: ${path}" -ForegroundColor Green
    } catch {
        Write-Host "Error updating permissions for ${path}: $_" -ForegroundColor Red
    }

    # Verify new permissions
    Write-Host "`nNew permissions set for ${path}:" -ForegroundColor Yellow
    (Get-Acl $path).Access | Format-Table IdentityReference,FileSystemRights -AutoSize
}
