
# Collect SHARE permissions for every shared folder on this server.
# Requires Windows Server 2012+ (SMB cmdlets). For Server 2003/2008 use the WMI version below.

# Exclude the built-in administrative shares (C$, ADMIN$, IPC$, etc.). Set to $false to include them.
$excludeAdminShares = $true

$shares = Get-SmbShare
if ($excludeAdminShares) {
    $shares = $shares | Where-Object { -not $_.Special }
}

$report = foreach ($share in $shares) {
    Get-SmbShareAccess -Name $share.Name -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            ShareName   = $share.Name
            SharePath   = $share.Path
            Description = $share.Description
            Account     = $_.AccountName
            AccessType  = $_.AccessControlType   # Allow / Deny
            AccessRight = $_.AccessRight          # Full / Change / Read
        }
    }
}

# Show on screen
$report | Format-Table -AutoSize

# Save to CSV next to the script
$report | Export-Csv -Path ".\Share_Permissions.csv" -NoTypeInformation
Write-Host "`nSaved $($report.Count) permission entries to Share_Permissions.csv"
