
# Windows Server 2008 / 2008 R2 (PowerShell 2.0) compatible version of
# Collect-ShareOpenFiles.ps1.
#
# Server 2008 has neither Get-SmbOpenFile (SMB module is 2012+) nor Export-Csv -Append
# (added in PowerShell 3.0), so this uses the built-in openfiles.exe and appends with
# Out-File instead.
#
# NOTE: openfiles.exe lists files opened OVER THE NETWORK by default. To also list files
# opened by local processes you must run "openfiles /local on" once and reboot -- not
# needed for a file share, where access is remote.
#
# Meant to run hourly via Task Scheduler; each run appends one snapshot to a monthly CSV.

$logDir     = "C:\temp\ShareUsageLogs"
$pathFilter = ""   # e.g. "G:\Group_Windt132k\Shared"; leave "" to log all open files

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$now     = Get-Date
$stamp   = $now.ToString("yyyy-MM-dd HH:mm:ss")
$logFile = Join-Path $logDir ("ShareOpenFiles_{0:yyyy-MM}.csv" -f $now)

# openfiles /query /fo csv /v emits 7 columns, in this fixed order:
#   Hostname, ID, Accessed By, Type, #Locks, Open Mode, Open File (Path\executable)
# The actual header TEXT varies by OS build/locale, so we bind by POSITION with our own
# header names and drop openfiles' own header row (Select-Object -Skip 1). This is why
# the earlier by-name version produced blank columns.
$cols = 'Hostname','ID','AccessedBy','Type','Locks','OpenMode','OpenPath'
$raw  = openfiles /query /fo csv /v 2>$null |
        ConvertFrom-Csv -Header $cols |
        Select-Object -Skip 1

$snapshot = foreach ($r in $raw) {
    $path = $r.OpenPath
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ($pathFilter -and ($path -notlike "$pathFilter*")) { continue }

    [PSCustomObject]@{
        Timestamp  = $stamp
        User       = $r.AccessedBy
        OpenId     = $r.ID
        OpenMode   = $r.OpenMode
        Path       = $path
    }
}

if ($snapshot) {
    # Build CSV text by hand so we can append without Export-Csv -Append (PS 3.0+)
    $lines = $snapshot | ConvertTo-Csv -NoTypeInformation

    if (Test-Path $logFile) {
        # File exists -> drop the header line before appending
        $lines = $lines | Select-Object -Skip 1
    }
    $lines | Out-File -FilePath $logFile -Encoding ASCII -Append

    Write-Host ("{0}: logged {1} open handle(s) to {2}" -f $stamp, $snapshot.Count, $logFile)
} else {
    Write-Host ("{0}: no open files matched." -f $stamp)
}
