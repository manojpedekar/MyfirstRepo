<#
.SYNOPSIS
    Exports all GPOs in a domain to individual XML reports.

.DESCRIPTION
    Exports every GPO in the specified domain to an XML report named after the GPO's
    display name. Run this once per domain, then use Search-GPOReports.ps1 to search the
    exported reports for any string (UNC path, server name, registry key, etc.).

.PARAMETER Domain
    The Active Directory domain to export GPOs from. Required -- you are prompted if omitted.

.PARAMETER ReportPath
    Folder where the XML reports are written. Created if it does not exist.
    Defaults to "C:\Temp\GPOReports".

.EXAMPLE
    .\Export_GPO_Find_GPO.ps1 -Domain "ssnc.global"
    Exports all GPOs from ssnc.global to C:\Temp\GPOReports.

.EXAMPLE
    .\Export_GPO_Find_GPO.ps1 -Domain "contoso.com" -ReportPath "E:\GPOReports"
    Exports all GPOs from contoso.com to E:\GPOReports.

.NOTES
    To search the exported reports afterwards:
        .\Search-GPOReports.ps1 -SearchString "\\windt132k.ssnc.global\Group" -ReportPath "C:\Temp\GPOReports"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [string]$ReportPath = "C:\Temp\GPOReports"
)

# Ensure the GroupPolicy module is available before doing anything.
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    throw "The GroupPolicy module is not installed. Install RSAT: Group Policy Management Tools."
}
Import-Module GroupPolicy -ErrorAction Stop

# Create the output folder if it does not already exist.
New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null

Write-Host "Exporting GPOs from '$Domain' to '$ReportPath'..." -ForegroundColor Cyan

$gpos = Get-GPO -All -Domain $Domain
foreach ($gpo in $gpos) {
    # Replace characters that are illegal in file names.
    $safeName = ($gpo.DisplayName -replace '[\\/:*?"<>|]', '_')
    $outFile  = Join-Path $ReportPath "$safeName.xml"

    try {
        Get-GPOReport -Guid $gpo.Id -Domain $Domain -ReportType XML -Path $outFile
    }
    catch {
        Write-Warning "Failed to export '$($gpo.DisplayName)': $($_.Exception.Message)"
    }
}

Write-Host "Exported $($gpos.Count) GPO report(s) to '$ReportPath'." -ForegroundColor Green
Write-Host "To search them, run: .\Search-GPOReports.ps1 -SearchString '<string>' -ReportPath '$ReportPath'" -ForegroundColor Cyan
