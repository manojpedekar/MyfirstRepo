$Destination = "\\wdc-pure-fb-01-data-vif01.ssnc-corp.cloud\TABusTechShare"
$Folders = Get-Content "C:\temp\manoj\FolderList.txt"

foreach ($SourceFolder in $Folders) {
    $FolderName = Split-Path $SourceFolder -Leaf
    $LogFile = "C:\temp\manoj\Robocopy_logs\${FolderName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    robocopy $SourceFolder (Join-Path $Destination $FolderName) /MIR /COPY:DAT /DCOPY:T /ZB /MT:16 /R:1 /W:1 /NDL /NFL /NP /LOG:$LogFile
}
