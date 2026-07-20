
# Directory whose one-level sub-folders you want to measure
$parent = "G:\Group_Windt132k\Shared"

# Get each immediate (one-level) sub-folder and its total size
$report = Get-ChildItem -Path $parent -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $totalSize = (Get-ChildItem $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum

    [PSCustomObject]@{
        FolderName = $_.Name
        FolderPath = $_.FullName
        SizeGB     = "{0:N2}" -f ($totalSize / 1GB)
    }
}

# Show on screen
$report | Format-Table -AutoSize

# Also save to CSV next to the script
$report | Export-Csv -Path ".\ShareFolder_Sizes.csv" -NoTypeInformation
Write-Host "`nSaved results to ShareFolder_Sizes.csv"
