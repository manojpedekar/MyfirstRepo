Import-Module GroupPolicy

$Domain = "ssnc.global"
$ReportPath = "C:\Temp\GPOReports"

New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null

Get-GPO -All -Domain $Domain | ForEach-Object {
    $SafeName = ($_.DisplayName -replace '[\\/:*?"<>|]', '_')
    Get-GPOReport -Guid $_.Id `
                  -Domain $Domain `
                  -ReportType XML `
                  -Path "$ReportPath\$SafeName.xml"
}

#Below command to be used to scan all exported gpo xml files and see which file have below string in it. This will help us to find which gpo have this string in it.
Get-ChildItem "$ReportPath\*.xml" | Select-String "\\windt132k.ssnc.global\Group"
