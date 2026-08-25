<#
.SYNOPSIS
    Exports the user members of an Active Directory security group to a timestamped CSV.

.DESCRIPTION
    Consolidates two legacy scripts into one parameterized tool:

        Export_Userlist_from_DoaminLocal_SG.ps1   (flat 'member' expansion, resolved via GC)
        Export_Userlist_from_SG_Recursive.ps1      (recursive membership via Get-ADGroupMember)

    Two resolution strategies are supported:

      * Default (flat): reads the group's 'member' attribute and resolves each member against a
        Global Catalog. This correctly resolves members that live in *other* domains of the
        forest - the common case for domain-local / cross-domain groups.

      * -Recursive: uses Get-ADGroupMember -Recursive to expand nested groups. Faster to write
        but does NOT return foreign-security-principal members from trusted/other forests, and
        cannot page arbitrarily deep cross-domain nesting. Use when the group and all members
        live in the same domain and you need nested expansion.

    Requires the ActiveDirectory module (RSAT / ADWS).

.PARAMETER GroupName
    sAMAccountName (or DN) of the group. Mandatory.

.PARAMETER Server
    Domain or domain controller hosting the group. Mandatory.

.PARAMETER Recursive
    Expand nested group membership via Get-ADGroupMember -Recursive (same-forest only).

.PARAMETER GlobalCatalog
    Global Catalog endpoint used to resolve members in the default (flat) mode.
    Defaults to "<Server>:3268".

.PARAMETER OutputPath
    Folder for the CSV and log. Created if missing. Defaults to "C:\temp".

.PARAMETER LogPath
    Optional log-file path. Defaults to a timestamped log under -OutputPath.

.EXAMPLE
    .\Get-ADGroupMemberReport_v1.ps1 -GroupName "WINDT132K_Share_W" -Server "ssnc.global"
    Flat membership resolved via the ssnc.global Global Catalog.

.EXAMPLE
    .\Get-ADGroupMemberReport_v1.ps1 -GroupName "SSNC_Windt132kgroup" -Server "globeop.com" -Recursive

.NOTES
    Returns the member objects to the pipeline; the CSV/log are side effects.
    Requires the ActiveDirectory PowerShell module.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [switch]$Recursive,

    [string]$GlobalCatalog,

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

function ConvertTo-MemberRecord {
    # Normalizes an AD user object into the report shape.
    param($User)
    [PSCustomObject]@{
        Username          = $User.SamAccountName
        FirstName         = $User.GivenName
        LastName          = $User.Surname
        Enabled           = $User.Enabled
        DistinguishedName = $User.DistinguishedName
    }
}
#endregion

#region Prerequisites
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw "The ActiveDirectory module is not installed. Install RSAT: Active Directory tools."
}
Import-Module ActiveDirectory -ErrorAction Stop

try {
    New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    throw "Failed to create output folder '$OutputPath': $($_.Exception.Message)"
}

if (-not $GlobalCatalog) { $GlobalCatalog = "${Server}:3268" }

$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
# Sanitize the group name for use in a file name.
$safeGroup = ($GroupName -replace '[\\/:*?"<>|,= ]', '_')
if (-not $LogPath) {
    $LogPath = Join-Path -Path $OutputPath -ChildPath "GroupMembers_${safeGroup}_$timestamp.log"
}
$csvPath = Join-Path -Path $OutputPath -ChildPath "GroupMembers_${safeGroup}_$timestamp.csv"

$userProps = @('GivenName', 'Surname', 'Enabled')
#endregion

#region Main processing
$mode = if ($Recursive) { 'Recursive (Get-ADGroupMember)' } else { "Flat (member attribute, GC '$GlobalCatalog')" }
Write-Log -Message "Resolving members of '$GroupName' on '$Server'. Mode: $mode." -Path $LogPath

$members = [System.Collections.Generic.List[object]]::new()
try {
    if ($Recursive) {
        # Nested expansion; filter to user objects only, then hydrate identity attributes.
        Get-ADGroupMember -Identity $GroupName -Server $Server -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'user' } |
            ForEach-Object {
                try {
                    $u = Get-ADUser -Identity $_.DistinguishedName -Server $Server -Properties $userProps -ErrorAction Stop
                    $members.Add((ConvertTo-MemberRecord -User $u))
                }
                catch {
                    Write-Log -Message "Could not resolve user '$($_.SamAccountName)': $($_.Exception.Message)" -Level WARN -Path $LogPath
                }
            }
    }
    else {
        # Flat 'member' DNs resolved against the Global Catalog (handles cross-domain members).
        $memberDns = @(Get-ADGroup -Identity $GroupName -Server $Server -Properties Member -ErrorAction Stop |
                       Select-Object -ExpandProperty Member)

        foreach ($dn in $memberDns) {
            try {
                $u = Get-ADUser -Identity $dn -Server $GlobalCatalog -Properties $userProps -ErrorAction Stop
                $members.Add((ConvertTo-MemberRecord -User $u))
            }
            catch {
                # Non-user members (nested groups, contacts, computers) or unresolvable DNs land here.
                Write-Log -Message "Skipped member (not a resolvable user) '$dn': $($_.Exception.Message)" -Level WARN -Path $LogPath
            }
        }
    }
}
catch {
    Write-Log -Message "Failed to read group '$GroupName' on '$Server': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    throw
}
#endregion

#region Summary
if ($members.Count -gt 0) {
    try {
        $members | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log -Message "Export complete. $($members.Count) user member(s) written to '$csvPath'." -Level SUCCESS -Path $LogPath
    }
    catch {
        Write-Log -Message "Failed to write CSV '$csvPath': $($_.Exception.Message)" -Level ERROR -Path $LogPath
    }
}
else {
    Write-Log -Message "No user members found in '$GroupName'." -Level WARN -Path $LogPath
}

$members
#endregion
