# Define file paths
$inputFile = ".\Russ_Revis_Folders.csv"          # Replace with your actual input file path
$outputFile = ".\folder_sizes.csv"    # Output file path

# Function to calculate folder size in MB
function Get-FolderSizeMB {
    param ($FolderPath)

    if (Test-Path $FolderPath) {
        $size = (Get-ChildItem -Path $FolderPath -Recurse -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum).Sum
        return [math]::Round($size / 1MB, 2)
    } else {
        return "Path Not Found"
    }
}

# Read the CSV and process each row
$results = Import-Csv -Path $inputFile | ForEach-Object {
    $folderSizeMB = Get-FolderSizeMB -FolderPath $_.folderPath
    $_ | Add-Member -NotePropertyName FolderSizeMB -NotePropertyValue $folderSizeMB -Force
    $_
}

# Export the results
$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host "Folder size report exported to $outputFile"
