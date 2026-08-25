<#
.SYNOPSIS
    Reports each home-directory folder alongside its Active Directory account status, to help
    identify departed-user folders that can be archived or removed.

.DESCRIPTION
    Consolidates two legacy scripts into one tool:

        Departed_users_Information.ps1   (folder + AD status only)
        Departed_users_FolderReport.ps1  (folder + AD status + size + last-modified)

    For every immediate subfolder of -HomeDirsPath the folder name is treated as a
    sAMAccountName and checked against AD via System.DirectoryServices (no module required).
    Each folder's account status is classified as Enabled / Disabled / Missing / ConnectionError.

    Folder size and most-recent-file activity (the expensive recursive scan) are collected only
    when -IncludeFolderStats is specified, since account status alone is often all that is needed.

    Output is written to a timestamped CSV under -OutputPath.

.PARAMETER HomeDirsPath
    Root path whose subfolders are the per-user home directories. Mandatory.

.PARAMETER Domain
    AD domain to check accounts against. If omitted, the current domain is used.

.PARAMETER IncludeFolderStats
    Also compute SizeMB and LastModified per folder (recursive; slower on large shares).

.PARAMETER OutputPath
    Folder for the CSV and log. Created if missing. Defaults to "C:\temp".

.PARAMETER LogPath
    Optional log-file path. Defaults to a timestamped log under -OutputPath.

.EXAMPLE
    .\Get-HomeDirUserStatus_v1.ps1 -HomeDirsPath "D:\Homedirs" -Domain "ad.dstsystems.com"

.EXAMPLE
    .\Get-HomeDirUserStatus_v1.ps1 -HomeDirsPath "D:\Homedirs" -Domain "ad.dstsystems.com" -IncludeFolderStats

.NOTES
    No module dependencies (uses System.DirectoryServices). Returns objects to the pipeline.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HomeDirsPath,

    [string]$Domain,

    [switch]$IncludeFolderStats,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = 'C:\temp',

    [string]$LogPath
)

#region Helper functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO',
        [string]$Path
    )
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line  = "$stamp [$Level] $Message"
    switch ($Level) {
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
    if ($Path) {
        try   { Add-Content -Path $Path -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Host "$stamp [WARN] Could not write log '$Path': $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

function Test-ADUserExists {
<#
    .SYNOPSIS
        Returns the AD status of a sAMAccountName as 'Enabled', 'Disabled', 'Missing', or
        'ConnectionError', using System.DirectoryServices (no ActiveDirectory module).
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$UserName,
        [string]$DomainName
    )

    $root     = $null
    $searcher = $null
    try {
        if ($DomainName) {
            $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainName")
        }
        else {
            $currentDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
            $root = $currentDomain.GetDirectoryEntry()
        }

        # Escape LDAP-special characters so a folder name cannot break or widen the filter.
        $escaped = $UserName -replace '([\\*()\x00/])', '\$1'
        $filter  = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escaped))"

        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root, $filter, @('sAMAccountName', 'userAccountControl'))
        $match = $searcher.FindOne()

        if ($match) {
            if ($match.Properties['userAccountControl'].Count -gt 0) {
                $uac = $match.Properties['userAccountControl'][0]
                if ((($uac -band 2) -ne 0)) { return 'Disabled' } else { return 'Enabled' }
            }
            Write-Warning "Found '$UserName' but could not read userAccountControl."
            return 'ConnectionError'
        }
        return 'Missing'
    }
    catch {
        Write-Warning "AD lookup failed for '$UserName': $_"
        return 'ConnectionError'
    }
    finally {
        if ($searcher) { $searcher.Dispose() }
        if ($root)     { $root.Dispose() }
    }
}
#endregion

#region Prerequisites
if (-not (Test-Path -LiteralPath $HomeDirsPath)) {
    throw "Home directory path '$HomeDirsPath' was not found. Check -HomeDirsPath and try again."
}

try {
    New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    throw "Failed to create output folder '$OutputPath': $($_.Exception.Message)"
}

$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $LogPath) {
    $LogPath = Join-Path -Path $OutputPath -ChildPath "HomeDirUserStatus_$timestamp.log"
}
$csvPath = Join-Path -Path $OutputPath -ChildPath "HomeDirUserStatus_$timestamp.csv"

$statusNotes = @{
    'Enabled'         = 'Account exists and is active'
    'Disabled'        = 'Account exists but is disabled'
    'Missing'         = 'No matching AD account (possible departed user)'
    'ConnectionError' = 'AD domain not available / status unreadable - no action taken'
}
#endregion

#region Main processing
$dirs = @(Get-ChildItem -LiteralPath $HomeDirsPath -Directory)
Write-Log -Message "Processing $($dirs.Count) folder(s) under '$HomeDirsPath'. IncludeFolderStats=$($IncludeFolderStats.IsPresent)." -Path $LogPath

$report = [System.Collections.Generic.List[object]]::new()
foreach ($dir in $dirs) {
    $status = Test-ADUserExists -UserName $dir.BaseName -DomainName $Domain
    $note   = if ($statusNotes.ContainsKey($status)) { $statusNotes[$status] } else { 'Unexpected status' }

    $record = [ordered]@{
        UserID = $dir.BaseName
        Status = $status
        Note   = $note
    }

    if ($IncludeFolderStats) {
        # Folder timestamps do not change when nested files change, so use the newest file.
        $files = Get-ChildItem -LiteralPath $dir.FullName -File -Recurse -Force -ErrorAction SilentlyContinue
        if ($files) {
            $record.SizeMB       = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            $record.LastModified = ($files | Measure-Object -Property LastWriteTime -Maximum).Maximum
        }
        else {
            $record.SizeMB       = 0
            $record.LastModified = $dir.LastWriteTime
        }
    }

    $record.FolderPath = $dir.FullName
    $report.Add([PSCustomObject]$record)
}
#endregion

#region Summary
if ($report.Count -gt 0) {
    try {
        $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        $missing = @($report | Where-Object { $_.Status -eq 'Missing' }).Count
        Write-Log -Message "Export complete. $($report.Count) folder(s) written to '$csvPath'. Missing accounts: $missing." -Level SUCCESS -Path $LogPath
    }
    catch {
        Write-Log -Message "Failed to write CSV '$csvPath': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    }
}
else {
    Write-Log -Message "No subfolders found under '$HomeDirsPath'." -Level WARN -Path $LogPath
}

$report
#endregion
