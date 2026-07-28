
# Report which top-level sub-folders on a share have had activity in the last N days,
# so the owners can be identified for a file migration.
#
# "Activity" = the most recent LastWriteTime of ANY file under the folder (recursive).
# A folder's own timestamp is not reliable because it does not update when a file
# deep inside it changes, so we scan the files.
#
# "Owner" = the NTFS owner recorded on the top-level folder's ACL. This is usually
# the person/group that created it. Share-level permissions are separate (see
# Windows_Share_Permissions.ps1).

# Root whose immediate (one-level) sub-folders you want to inspect
$parent = "G:\Group_Windt132k\Shared"

# Look-back window
$days       = 30
$cutoff     = (Get-Date).AddDays(-$days)
$reportPath = ".\ShareFolder_Activity.csv"

$report = Get-ChildItem -Path $parent -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $folder = $_

    # Newest file write time anywhere under this folder
    $lastWrite = Get-ChildItem $folder.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property LastWriteTime -Maximum |
                 Select-Object -ExpandProperty Maximum

    # NTFS owner of the top-level folder
    $owner = try { (Get-Acl $folder.FullName -ErrorAction Stop).Owner } catch { "<unreadable>" }

    [PSCustomObject]@{
        FolderName   = $folder.Name
        FolderPath   = $folder.FullName
        Owner        = $owner
        LastActivity = $lastWrite
        ActiveIn30d  = ($lastWrite -ne $null -and $lastWrite -ge $cutoff)
    }
}

# Show only the folders with recent activity, newest first
$active = $report | Where-Object { $_.ActiveIn30d } | Sort-Object LastActivity -Descending

Write-Host ("Folders with activity in the last {0} days (cutoff {1:yyyy-MM-dd}):" -f $days, $cutoff)
$active | Format-Table FolderName, Owner, LastActivity -AutoSize

# Save the full report (active flag included) next to the script
$report | Sort-Object LastActivity -Descending | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "`nSaved full report ($($report.Count) folders, $($active.Count) active) to $reportPath"
