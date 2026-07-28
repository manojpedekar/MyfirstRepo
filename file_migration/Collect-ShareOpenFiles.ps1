
# Snapshot the files/folders currently open over this server's SMB shares, and who
# has them open. Meant to run hourly via Task Scheduler; each run APPENDS one snapshot
# to a monthly CSV so that, over time, you build a picture of who actually uses the share.
#
# Get-SmbOpenFile only shows handles open AT THE MOMENT it runs, so frequent snapshots
# matter -- an hourly cadence catches most working-hours activity. For a complete record
# of every access (including brief ones), object-access auditing is the authoritative
# source (see enable_audit_policy / Read_Shared_Audit_Event in this folder).
#
# Requires Windows Server 2012+ (SMB cmdlets) and admin rights.

# Where to write the rolling logs. One CSV per month keeps files manageable.
$logDir = "C:\ShareUsageLogs"

# Optional: only keep opens whose path starts with this root. Leave "" to log all shares.
$pathFilter = ""

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$now     = Get-Date
$logFile = Join-Path $logDir ("ShareOpenFiles_{0:yyyy-MM}.csv" -f $now)

$open = Get-SmbOpenFile -ErrorAction SilentlyContinue

if ($pathFilter) {
    $open = $open | Where-Object { $_.Path -like "$pathFilter*" }
}

$snapshot = foreach ($f in $open) {
    [PSCustomObject]@{
        Timestamp    = $now.ToString("yyyy-MM-dd HH:mm:ss")
        User         = $f.ClientUserName
        ClientHost   = $f.ClientComputerName
        Path         = $f.Path
        ShareName    = $f.ShareRelativePath
        FileId       = $f.FileId
    }
}

if ($snapshot) {
    # Append; Export-Csv -Append writes the header itself when the file is new
    $snapshot | Export-Csv -Path $logFile -NoTypeInformation -Append
    Write-Host ("{0}: logged {1} open handle(s) to {2}" -f $now, $snapshot.Count, $logFile)
} else {
    Write-Host ("{0}: no open files matched." -f $now)
}
