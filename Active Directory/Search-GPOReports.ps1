<#
.SYNOPSIS
    Searches already-exported GPO XML reports for a string.

.DESCRIPTION
    Scans a folder of GPO XML reports (produced by Export_GPO_Find_GPO.ps1) for a search
    string and reports which GPOs contain it, on which line, and the matching text.
    Export the domain's GPOs once, then run this as many times as you like with different
    search strings -- no need to re-export.

.PARAMETER SearchString
    The string to search for (e.g. a UNC path, server name, registry key, or account).

.PARAMETER ReportPath
    Folder containing the exported XML reports. Defaults to "C:\Temp\GPOReports".

.PARAMETER Regex
    Treat SearchString as a regular expression. By default the search is a literal
    (simple) match, which is safest for strings containing \ : . * etc.

.PARAMETER CsvPath
    Optional path to also write the results to a CSV file.

.EXAMPLE
    .\Search-GPOReports.ps1 -SearchString "\\windt132k.ssnc.global\Group"
    Lists every GPO whose report references that UNC path.

.EXAMPLE
    .\Search-GPOReports.ps1 -SearchString "logon.bat" -ReportPath "E:\GPOReports" -CsvPath "C:\Temp\hits.csv"
    Searches reports in E:\GPOReports and saves the matches to a CSV.

.EXAMPLE
    .\Search-GPOReports.ps1 -SearchString "Admin.*Prod" -Regex
    Searches using a regular expression.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SearchString,

    [string]$ReportPath = "C:\Temp\GPOReports",

    [switch]$Regex,

    [string]$CsvPath
)

if (-not (Test-Path -Path $ReportPath)) {
    throw "Report folder '$ReportPath' not found. Run Export_GPO_Find_GPO.ps1 first."
}

$xmlFiles = Get-ChildItem -Path $ReportPath -Filter *.xml
if (-not $xmlFiles) {
    throw "No .xml reports found in '$ReportPath'. Run Export_GPO_Find_GPO.ps1 first."
}

Write-Host "Searching $($xmlFiles.Count) report(s) in '$ReportPath' for '$SearchString'..." -ForegroundColor Cyan

# Literal match by default (-SimpleMatch); regex only when -Regex is specified.
$selectParams = @{ Pattern = $SearchString }
if (-not $Regex) { $selectParams.SimpleMatch = $true }

$results = $xmlFiles |
    Select-String @selectParams |
    Select-Object @{Name = 'GPO';        Expression = { $_.Filename -replace '\.xml$', '' }},
                  @{Name = 'LineNumber';  Expression = { $_.LineNumber }},
                  @{Name = 'Match';       Expression = { $_.Line.Trim() }}

if ($results) {
    $results | Format-Table -AutoSize

    # De-duplicated list of GPO names that matched, for a quick summary.
    $gpoNames = $results.GPO | Sort-Object -Unique
    Write-Host "`nMatched in $($gpoNames.Count) GPO(s):" -ForegroundColor Green
    $gpoNames | ForEach-Object { Write-Host "  - $_" }

    if ($CsvPath) {
        $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nResults written to '$CsvPath'." -ForegroundColor Green
    }
}
else {
    Write-Host "No reports contained '$SearchString'." -ForegroundColor Yellow
}
