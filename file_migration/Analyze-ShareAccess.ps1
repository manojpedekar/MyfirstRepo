param(
    [string]$LogDir = "$PSScriptRoot\ShareAccessLogs"
)

$master = Join-Path $LogDir 'OpenFiles_Master.csv'
$rows = Import-Csv $master | Where-Object {
    $_.AccessedBy -and $_.AccessedBy -ne 'N/A' -and
    $_.OpenFile -match '^[A-Za-z]:\\'
}

# Trim stray whitespace produced by openfiles /v output
foreach ($r in $rows) {
    $r.AccessedBy = $r.AccessedBy.Trim()
    $r.OpenFile   = $r.OpenFile.Trim()
    $r.OpenMode   = $r.OpenMode.Trim()
    $r.Hostname   = $r.Hostname.Trim()
}

$writeModes = @('Write','Write + Read','Read + Write')

Write-Output "==================== OVERVIEW ===================="
Write-Output ("Valid share-open records : {0}" -f $rows.Count)
$span = $rows | Measure-Object SnapshotTime -Minimum -Maximum
Write-Output ("Snapshot window          : {0}  ->  {1}" -f $span.Minimum, $span.Maximum)
Write-Output ("Distinct snapshots        : {0}" -f ($rows.SnapshotTime | Sort-Object -Unique).Count)
Write-Output ("Distinct users            : {0}" -f ($rows.AccessedBy | Sort-Object -Unique).Count)
Write-Output ("Distinct hosts (servers)  : {0}  [{1}]" -f ($rows.Hostname | Sort-Object -Unique).Count, (($rows.Hostname | Sort-Object -Unique) -join ', '))
$writeRows = $rows | Where-Object { $writeModes -contains $_.OpenMode }
Write-Output ("Write-mode opens          : {0} ({1:P1} of records)" -f $writeRows.Count, ($writeRows.Count / [double]$rows.Count))

Write-Output ""
Write-Output "==================== TOP USERS (by open events) ===================="
$rows | Group-Object AccessedBy | Sort-Object Count -Descending | Select-Object -First 20 |
    ForEach-Object { "{0,-18} {1,6}" -f $_.Name, $_.Count }

Write-Output ""
Write-Output "==================== USERS WHO WROTE (had Write mode at least once) ===================="
$writeRows | Group-Object AccessedBy | Sort-Object Count -Descending |
    ForEach-Object { "{0,-18} {1,6} write-opens" -f $_.Name, $_.Count }

Write-Output ""
Write-Output "==================== TOP-LEVEL SHARE ROOTS ===================="
$rows | ForEach-Object {
    $p = $_.OpenFile -replace '^[A-Za-z]:\\',''
    ($p -split '\\')[0]
} | Group-Object | Sort-Object Count -Descending |
    ForEach-Object { "{0,8}  {1}" -f $_.Count, $_.Name }

Write-Output ""
Write-Output "==================== BUSIEST TOP-2 FOLDERS ===================="
$rows | ForEach-Object {
    $p = $_.OpenFile -replace '^[A-Za-z]:\\',''
    ($p -split '\\' | Select-Object -First 3) -join '\'
} | Group-Object | Sort-Object Count -Descending | Select-Object -First 25 |
    ForEach-Object { "{0,6}  {1}" -f $_.Count, $_.Name }

Write-Output ""
Write-Output "==================== ACTIVITY BY DATE ===================="
$rows | ForEach-Object { ($_.SnapshotTime -split ' ')[0] } |
    Group-Object | Sort-Object Name |
    ForEach-Object { "{0}  {1,6} opens" -f $_.Name, $_.Count }

Write-Output ""
Write-Output "==================== ACTIVITY BY HOUR OF DAY ===================="
$rows | ForEach-Object {
    $t = ($_.SnapshotTime -split ' ')[1]
    ($t -split ':')[0]
} | Group-Object | Sort-Object Name |
    ForEach-Object { "{0}:00  {1,6} opens" -f $_.Name, $_.Count }

Write-Output ""
Write-Output "==================== DISTINCT FILES CURRENTLY-IN-USE (unique paths) ===================="
Write-Output ("Distinct file/folder paths observed: {0}" -f ($rows.OpenFile | Sort-Object -Unique).Count)
$fileRows = $rows | Where-Object { $_.OpenFile -match '\.[A-Za-z0-9]{1,5}$' }
Write-Output ("  of which look like files (have extension): {0}" -f ($fileRows.OpenFile | Sort-Object -Unique).Count)
Write-Output ""
Write-Output "File types (by extension) among opened files:"
$fileRows | ForEach-Object {
    if ($_.OpenFile -match '\.([A-Za-z0-9]{1,5})$') { $matches[1].ToLower() } else { 'other' }
} | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
    ForEach-Object { "{0,6}  .{1}" -f $_.Count, $_.Name }
