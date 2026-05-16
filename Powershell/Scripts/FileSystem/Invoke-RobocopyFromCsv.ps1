# Path to your CSV
$csvPath = ".\inputfile-folderpaths.csv"

# Import CSV with: FolderName, Source_Folder, Destination_Folder
$data = Import-Csv -Path $csvPath

# Timestamp for logs
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

foreach ($entry in $data) {
    $folderName = $entry.FolderName
    $source = $entry.Source_Folder.TrimEnd('\')
    $dest = $entry.Destination_Folder.TrimEnd('\')
    $desc = "ROBO_ADD-Description_$folderName`_2_Isilon" -replace '[\\/:*?"<>|]', '_'
    $logFile = "$desc" + "_$timestamp.log"

    Write-Host "`n=============================="
    Write-Host "Starting Robocopy for: $folderName"
    Write-Host "Source: $source"
    Write-Host "Destination: $dest"
    Write-Host "Log: $logFile"
    Write-Host "==============================`n"

    # Run robocopy with proper quoting
    & robocopy "$source" "$dest" /S /E /COPY:DAT /R:0 /W:0 /LOG:"$logFile"
}
