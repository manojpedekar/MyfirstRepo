
# Roll up the hourly snapshots produced by Collect-ShareOpenFiles.ps1 into a per-folder
# summary: for each top-level folder under a share, which users touched it, how many
# times they were seen, and when they were last seen. This is what you use to find the
# real owners/active users for the migration.

$logDir     = "C:\ShareUsageLogs"
$reportPath = ".\ShareUsage_Summary.csv"

# Depth of the folder to group by, relative to the share root in the logged Path.
# e.g. \\srv\share\TeamA\Sub\file.xlsx -> level 1 groups by "TeamA".
$groupLevel = 1

$rows = Get-ChildItem -Path $logDir -Filter "ShareOpenFiles_*.csv" -ErrorAction SilentlyContinue |
        ForEach-Object { Import-Csv $_.FullName }

if (-not $rows) {
    Write-Host "No log rows found in $logDir. Has Collect-ShareOpenFiles.ps1 been running?"
    return
}

# Derive a grouping folder key from each logged path
$tagged = foreach ($r in $rows) {
    if ([string]::IsNullOrWhiteSpace($r.Path)) { continue }
    $parts  = $r.Path.TrimStart('\') -split '\\'
    # parts[0..1] on a UNC path are server + share; the folder we want sits after that
    $folder = ($parts | Select-Object -Skip (2 + $groupLevel - 1) -First 1)
    if (-not $folder) { $folder = "<root>" }

    $r | Add-Member -NotePropertyName Folder -NotePropertyValue $folder -PassThru
}

$summary = $tagged | Group-Object Folder, User | ForEach-Object {
    $g = $_.Group
    [PSCustomObject]@{
        Folder     = $g[0].Folder
        User       = $g[0].User
        TimesSeen  = $_.Count
        FirstSeen  = ($g.Timestamp | Measure-Object -Minimum).Minimum
        LastSeen   = ($g.Timestamp | Measure-Object -Maximum).Maximum
    }
} | Sort-Object Folder, { [int]$_.TimesSeen } -Descending

$summary | Format-Table -AutoSize
$summary | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "`nSaved usage summary to $reportPath"
