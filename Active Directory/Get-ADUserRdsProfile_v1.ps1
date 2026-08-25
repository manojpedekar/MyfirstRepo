<#
.SYNOPSIS
    Exports Remote Desktop Services (Terminal Services) profile attributes for AD users to a
    timestamped CSV.

.DESCRIPTION
    Replaces the legacy EXport_Userlist_with_TerminalProfilePath.ps1, which (a) contained a
    stray 'Or' line that made the script fail to run and (b) enumerated every user with
    Get-ADUser -Filter * and then opened a separate ADSI bind per user - unworkable at
    enterprise scale.

    This version:
      * Enumerates candidate users with a paged DirectorySearcher (no ActiveDirectory module
        required) and lets you scope the scan with -SearchBase and -LdapFilter instead of
        always reading the entire directory.
      * Reads the RDS attributes (ProfilePath, HomeDirectory, HomeDrive, AllowLogon) via the
        IADsTSUserEx interface. These live inside the serialized userParameters blob, so a
        per-user bind is required - but on PowerShell 7+ the binds run in parallel.

    Note: RDS attributes cannot be retrieved with a plain LDAP attribute query; the per-object
    COM bind is the supported Microsoft approach.

.PARAMETER Domain
    AD domain or domain controller to query. Mandatory.

.PARAMETER SearchBase
    Optional distinguished name to scope the search (e.g. an OU). Defaults to the domain root.

.PARAMETER LdapFilter
    LDAP filter selecting the users to inspect.
    Defaults to '(&(objectCategory=person)(objectClass=user))'.

.PARAMETER ThrottleLimit
    Maximum concurrent binds on PowerShell 7+. Ignored on 5.1. Defaults to 16.

.PARAMETER OutputPath
    Folder for the CSV and log. Created if missing. Defaults to "C:\temp".

.PARAMETER LogPath
    Optional log-file path. Defaults to a timestamped log under -OutputPath.

.EXAMPLE
    .\Get-ADUserRdsProfile_v1.ps1 -Domain "globeop.com"

.EXAMPLE
    .\Get-ADUserRdsProfile_v1.ps1 -Domain "globeop.com" -SearchBase "OU=Staff,DC=globeop,DC=com"

.NOTES
    No ActiveDirectory module dependency (uses System.DirectoryServices).
    Returns objects to the pipeline; pipe to Out-GridView for interactive review.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Domain,

    [string]$SearchBase,

    [ValidateNotNullOrEmpty()]
    [string]$LdapFilter = '(&(objectCategory=person)(objectClass=user))',

    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 16,

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
#endregion

#region Prerequisites
try {
    New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    throw "Failed to create output folder '$OutputPath': $($_.Exception.Message)"
}

$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $LogPath) {
    $LogPath = Join-Path -Path $OutputPath -ChildPath "ADUserRdsProfile_$timestamp.log"
}
$csvPath = Join-Path -Path $OutputPath -ChildPath "ADUserRdsProfile_$timestamp.csv"
#endregion

#region Main processing
Write-Log -Message "Enumerating users on '$Domain' (SearchBase: $(if ($SearchBase) { $SearchBase } else { '<domain root>' }))." -Path $LogPath

# Enumerate candidate users (sAMAccountName + DN only) with a single paged search.
$root     = $null
$searcher = $null
$userInfo = [System.Collections.Generic.List[object]]::new()
try {
    $ldapPath = if ($SearchBase) { "LDAP://$Domain/$SearchBase" } else { "LDAP://$Domain" }
    $root     = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
    $searcher.Filter   = $LdapFilter
    $searcher.PageSize = 1000
    [void]$searcher.PropertiesToLoad.AddRange(@('samaccountname', 'distinguishedname'))

    $found = $searcher.FindAll()
    foreach ($e in $found) {
        $userInfo.Add([PSCustomObject]@{
            SamAccountName    = [string]$e.Properties['samaccountname'][0]
            DistinguishedName = [string]$e.Properties['distinguishedname'][0]
        })
    }
    $found.Dispose()
}
catch {
    Write-Log -Message "Failed to enumerate users on '$Domain': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    throw
}
finally {
    if ($searcher) { $searcher.Dispose() }
    if ($root)     { $root.Dispose() }
}

Write-Log -Message "Found $($userInfo.Count) user(s). Reading RDS attributes..." -Path $LogPath

# Bind one user and read RDS attributes via IADsTSUserEx. Shared by parallel and sequential paths.
$readRds = {
    param($DomainName, $User)

    $rec = [PSCustomObject]@{
        SamAccountName = $User.SamAccountName
        ProfilePath    = $null
        HomeDirectory  = $null
        HomeDrive      = $null
        AllowLogon     = $null
        Error          = $null
    }
    try {
        $entry = [ADSI]"LDAP://$DomainName/$($User.DistinguishedName)"
        $rec.ProfilePath   = try { $entry.psbase.InvokeGet('TerminalServicesProfilePath') }   catch { $null }
        $rec.HomeDirectory = try { $entry.psbase.InvokeGet('TerminalServicesHomeDirectory') } catch { $null }
        $rec.HomeDrive     = try { $entry.psbase.InvokeGet('TerminalServicesHomeDrive') }     catch { $null }
        $rec.AllowLogon    = try { $entry.psbase.InvokeGet('AllowLogon') }                     catch { $null }
        $entry.psbase.Dispose()
    }
    catch {
        $rec.Error = $_.Exception.Message
    }
    $rec
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Log -Message "PowerShell 7+ detected; reading RDS attributes in parallel (throttle $ThrottleLimit)." -Path $LogPath
    $results = $userInfo | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $sb = [scriptblock]::Create($using:readRds)
        & $sb $using:Domain $_
    }
}
else {
    Write-Log -Message "Windows PowerShell $($PSVersionTable.PSVersion) detected; reading RDS attributes sequentially." -Path $LogPath
    $results = foreach ($u in $userInfo) { & $readRds $Domain $u }
}

$results = @($results)
$errorCount = @($results | Where-Object { $_.Error }).Count
if ($errorCount -gt 0) {
    Write-Log -Message "$errorCount user(s) could not be read (see 'Error' column)." -Level WARN -Path $LogPath
}
#endregion

#region Summary
if ($results.Count -gt 0) {
    try {
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log -Message "Export complete. $($results.Count) user(s) written to '$csvPath'." -Level SUCCESS -Path $LogPath
    }
    catch {
        Write-Log -Message "Failed to write CSV '$csvPath': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    }
}
else {
    Write-Log -Message "No users matched the filter." -Level WARN -Path $LogPath
}

# Emit objects to the pipeline; caller can pipe to Out-GridView or further filtering.
$results
#endregion
