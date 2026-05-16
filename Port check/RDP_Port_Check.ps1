#For RDP
$servers = Get-Content "C:\temp\test\servers-suitesolution.txt"
$results = @()

foreach ($server in $servers) {

    $test = Test-NetConnection -ComputerName $server -Port 3389 -WarningAction SilentlyContinue

    # Test-NetConnection returns RemoteAddress (IP)
    $ip = if ($test.RemoteAddress) { $test.RemoteAddress.IPAddressToString } else { "N/A" }

    $status = if ($test.TcpTestSucceeded) { "Success" } else { "Failed" }

    $results += [PSCustomObject]@{
        ServerName   = $server
        IPAddress    = $ip
        RDPStatus  = $status
    }
}

$results | Export-Csv -Path "C:\temp\test\RDP_Results.csv" -NoTypeInformation

Write-Host "CSV generated: C:\temp\test\RDP_Results.csv" -ForegroundColor Green
