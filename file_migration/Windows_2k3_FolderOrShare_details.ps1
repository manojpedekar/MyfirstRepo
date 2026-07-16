
$path = "G:\Group_Windt132k\Shared\REIT Team\Rompsen"

$items = Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue
$files = ($items | Where-Object { -not $_.PSIsContainer })
$folders = ($items | Where-Object { $_.PSIsContainer })
$totalSize = ($files | Measure-Object -Property Length -Sum).Sum

Write-Host "Path: $path"
Write-Host "Total Size: $("{0:N2}" -f ($totalSize / 1GB)) GB"
Write-Host "File Count: $($files.Count)"
Write-Host "Folder Count: $($folders.Count)"
