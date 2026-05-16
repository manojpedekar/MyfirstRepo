$servers = @("server1", "server2", "server3"
)
or 
$servers = Get-Content "E:\Manoj\saltupgrade\servers.txt"


$results = foreach ($server in $servers) {

    try {

        $disk = Invoke-Command -ComputerName $server -ScriptBlock {
            Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" |
            Select-Object @{
                Name="TotalSizeGB"
                Expression={[math]::Round($_.Size/1GB,2)}
            },
            @{
                Name="FreeSpaceGB"
                Expression={[math]::Round($_.FreeSpace/1GB,2)}
            }
        }

        [PSCustomObject]@{
            Server      = $server
            TotalSizeGB = $disk.TotalSizeGB
            FreeSpaceGB = $disk.FreeSpaceGB
        }

    }
    catch {

        [PSCustomObject]@{
            Server      = $server
            TotalSizeGB = "FAILED"
            FreeSpaceGB = "FAILED"
        }

    }
}

$results | Format-Table -AutoSize
$results | Export-Csv "C:\Temp\CDriveReport.csv" -NoTypeInformation
