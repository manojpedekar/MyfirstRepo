<#
.SYNOPSIS
    Searches already-exported GPO XML reports for a string.

.DESCRIPTION
    Recursively scans a folder of GPO XML reports (produced by Export_GPO_Find_GPO_v2.ps1)
    for a search string and reports which GPOs contain it, in which domain (subfolder),
    on which line, and the matching text. Because Export writes per-domain subfolders,
    the search is recursive by default so all domains under the root are covered.

    Export the domain's GPOs once, then run this as many times as you like with different
    search strings -- no need to re-export.

.PARAMETER SearchString
    The string to search for (e.g. a UNC path, server name, registry key, or account).

.PARAMETER ReportPath
    Root folder containing the exported XML reports (searched recursively).
    Defaults to "C:\Temp\GPOReports".

.PARAMETER Regex
    Treat SearchString as a regular expression. By default the search is a literal
    (simple) match, which is safest for strings containing \ : . * etc.

.PARAMETER CsvPath
    Optional path to also write the results to a CSV file. The parent folder is created
    if it does not exist.

.PARAMETER ContextLength
    Maximum characters of matching text to display/return per hit. GPO XML reports are
    frequently emitted as one very long line, so the raw match can be huge; this trims it
    to a readable window centred on the match. Defaults to 200. Use 0 for no trimming.

.EXAMPLE
    .\Search-GPOReports_v2.ps1 -SearchString "\\windt132k.ssnc.global\Group"
    Lists every GPO whose report references that UNC path, across all exported domains.

.EXAMPLE
    .\Search-GPOReports_v2.ps1 -SearchString "logon.bat" -ReportPath "E:\GPOReports" -CsvPath "C:\Temp\hits.csv"
    Searches reports in E:\GPOReports and saves the matches to a CSV.

.EXAMPLE
    .\Search-GPOReports_v2.ps1 -SearchString "Admin.*Prod" -Regex
    Searches using a regular expression.

.NOTES
    Returns PSCustomObject results to the pipeline; the console table/summary is display only.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchString,

    [ValidateNotNullOrEmpty()]
    [string]$ReportPath = "C:\Temp\GPOReports",

    [switch]$Regex,

    [string]$CsvPath,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$ContextLength = 200
)

#region Helper functions
function Write-Status {
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'SUCCESS')] [string]$Level = 'INFO'
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line      = "$timestamp [$Level] $Message"
    switch ($Level) {
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
}

function Get-MatchContext {
    # Trims a long matching line to a readable window centred on the first match.
    param(
        [string]$Line,
        [string]$Pattern,
        [bool]$IsRegex,
        [int]$MaxLength
    )

    $trimmed = $Line.Trim()
    if ($MaxLength -le 0 -or $trimmed.Length -le $MaxLength) {
        return $trimmed
    }

    # Locate the match so the window is centred on it rather than the start of the line.
    $index = -1
    if ($IsRegex) {
        $m = [regex]::Match($trimmed, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { $index = $m.Index }
    }
    else {
        $index = $trimmed.IndexOf($Pattern, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ($index -lt 0) { $index = 0 }

    $start = [Math]::Max(0, $index - [Math]::Floor($MaxLength / 2))
    $len   = [Math]::Min($MaxLength, $trimmed.Length - $start)
    $window = $trimmed.Substring($start, $len)

    $prefix = if ($start -gt 0) { '...' } else { '' }
    $suffix = if (($start + $len) -lt $trimmed.Length) { '...' } else { '' }
    return "$prefix$window$suffix"
}
#endregion

#region Prerequisites
if (-not (Test-Path -Path $ReportPath)) {
    throw "Report folder '$ReportPath' not found. Run Export_GPO_Find_GPO_v2.ps1 first."
}

# Recursive: Export writes per-domain subfolders, so search the whole tree.
$xmlFiles = @(Get-ChildItem -Path $ReportPath -Filter *.xml -File -Recurse)
if (-not $xmlFiles) {
    throw "No .xml reports found under '$ReportPath'. Run Export_GPO_Find_GPO_v2.ps1 first."
}

# Validate CSV target up front so we fail fast, before doing the work.
if ($CsvPath) {
    $csvParent = Split-Path -Path $CsvPath -Parent
    if ($csvParent -and -not (Test-Path -Path $csvParent)) {
        try   { New-Item -Path $csvParent -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        catch { throw "Cannot create CSV output folder '$csvParent': $($_.Exception.Message)" }
    }
}
#endregion

#region Main processing
Write-Status -Message "Searching $($xmlFiles.Count) report(s) under '$ReportPath' for '$SearchString'..."

# Literal match by default (-SimpleMatch); regex only when -Regex is specified.
$selectParams = @{ Pattern = $SearchString }
if (-not $Regex) { $selectParams.SimpleMatch = $true }

$rootFull = (Resolve-Path -Path $ReportPath).Path.TrimEnd('\')

$results = $xmlFiles |
    Select-String @selectParams |
    Select-Object @{Name = 'Domain';     Expression = {
                        # Derive the domain from the immediate subfolder under the root.
                        $dir = Split-Path -Path $_.Path -Parent
                        if ($dir.Length -gt $rootFull.Length) {
                            ($dir.Substring($rootFull.Length).TrimStart('\') -split '\\')[0]
                        } else { '' }
                  }},
                  @{Name = 'GPO';         Expression = { $_.Filename -replace '\.xml$', '' }},
                  @{Name = 'LineNumber';  Expression = { $_.LineNumber }},
                  @{Name = 'Match';       Expression = {
                        Get-MatchContext -Line $_.Line -Pattern $SearchString -IsRegex $Regex.IsPresent -MaxLength $ContextLength
                  }}
#endregion

#region Summary
if ($results) {
    $results | Format-Table -AutoSize | Out-Host

    # De-duplicated list of GPO names that matched, for a quick summary.
    $gpoNames = $results.GPO | Sort-Object -Unique
    Write-Status -Message "Matched in $($gpoNames.Count) GPO(s)." -Level SUCCESS
    $gpoNames | ForEach-Object { Write-Host "  - $_" }

    if ($CsvPath) {
        try {
            $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            Write-Status -Message "Results written to '$CsvPath'." -Level SUCCESS
        }
        catch {
            Write-Status -Message "Failed to write CSV '$CsvPath': $($_.Exception.Message)" -Level WARN
        }
    }

    # Emit objects to the pipeline (formatting above is display only).
    $results
}
else {
    Write-Status -Message "No reports contained '$SearchString'." -Level WARN
}
#endregion
