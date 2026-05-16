$servers = Get-Content -Path "C:\Temp\RDS\servers.txt"
$ErrorActionPreference = "Stop"
$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$errorLogFile = "C:\Temp\RDS\error_log_$dateTime.txt"
$Result=@()

Foreach ($server in $servers) {

    $ResultObject=[PSCustomObject]@{
        'Server Name'=''
        'Remote Desktop Service Role'=''
        'RDS Licensing Type'=''

    }

 Try{

#################### Capturing Remote Desktop Service Role and Licensing Mode Type details  #####################################

Write-host -ForegroundColor Green "Capturing Remote Desktop Service Role and Licensing Mode Type details for $($server)"
$s = New-PSSession -ComputerName $server
$rds= invoke-Command -Session $s -scriptblock {(Get-WmiObject -Namespace "root\CIMV2\TerminalServices" -Class "Win32_TerminalServiceSetting" -ErrorAction SilentlyContinue)}
        If($rds.TerminalServerMode -eq 1)
        {
        $RemoteDesktopServiceRole="Enabled"
        }
        else{
        $RemoteDesktopServiceRole="Not Enabled"
        }
Remove-PSSession -Session $s
$ResultObject.'Server Name' = $server
$ResultObject.'Remote Desktop Service Role' = $RemoteDesktopServiceRole
$ResultObject.'RDS Licensing Type' = $rds.LicensingName
$Result+=$ResultObject

        }

            Catch{
$ResultObject.'Server Name' = $server
$ResultObject.'Remote Desktop Service Role' = 'Failed'
$ResultObject.'RDS Licensing Type' = 'Failed'
$errorMessage = "${server}: Error occurred: $($_.Exception.Message)"
$errorMessage | Out-File -Append -FilePath $errorLogFile
                $Result+=$ResultObject

            }

}
$result | Export-Csv "E:\Temp\RDS\RDS_Server_Role_Details_$dateTime.csv" -NoTypeInformation
