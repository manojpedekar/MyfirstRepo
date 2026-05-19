#For RDP
$servers = Get-Content "E:\Manoj\rds\servers-suitesolution.txt"
$OutputPath = "E:\Manoj\rds\RDP_Results.csv"
$results = @()

foreach ($server in $servers) {

    $test = Test-NetConnection -ComputerName $server -Port 5985 -WarningAction SilentlyContinue

    # Test-NetConnection returns RemoteAddress (IP)
    $ip = if ($test.RemoteAddress) { $test.RemoteAddress.IPAddressToString } else { "N/A" }

    $status = if ($test.TcpTestSucceeded) { "Success" } else { "Failed" }

    $results += [PSCustomObject]@{
        ServerName   = $server
        IPAddress    = $ip
        RDPStatus  = $status
    }
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "CSV generated: $OutputPath -ForegroundColor Green
