$servers = Get-Content C:\temp\\UpdatePerms\ComputerList.txt

foreach ($Server in $Servers) {
    Write-Host $server
    Copy-Item -Path 'C:\temp\UpdatePerms' -Destination "\\$Server\C$\temp\UpdatePerms" -Recurse -Force
}
