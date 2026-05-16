$servers = Get-Content -Path "E:\Temp\RDS\servers.txt"
$ErrorActionPreference = "Stop"
$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$errorLogFile = "E:\Temp\RDS\error_log_$dateTime.txt"
$Result=@()

Foreach ($server in $servers) {

$ResultObject=[PSCustomObject]@{
'Server Name'=''
'LicenseServer'=''
'LicensingMode'=''
 }

    Try{

 # Server Name

$ResultObject.'Server Name' = $server

        # Terminal License Server Information
Write-host -ForegroundColor Green "capturing Terminal License Server Information for $($server)"
$s = New-PSSession -ComputerName $server
$LicenseServer = Invoke-Command -Session $s -ScriptBlock {Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows NT\Terminal Services\' -Name LicenseServers -ErrorAction SilentlyContinue}
$LicensingMode = Invoke-Command -Session  $s -ScriptBlock {Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows NT\Terminal Services\' -Name LicensingMode -ErrorAction SilentlyContinue}
Remove-PSSession -Session $s
$ResultObject.'LicenseServer' = $LicenseServer.LicenseServers -join ', '
$ResultObject.'LicensingMode' = $LicensingMode.LicensingMode

$Result+=$ResultObject

}

            Catch{
$ResultObject.'Server Name' = $server
$ResultObject.'LicenseServer' = 'Failed'
$ResultObject.'LicensingMode' = 'Failed'
$errorMessage = "${server}: Error occurred: $($_.Exception.Message)"
$errorMessage | Out-File -Append -FilePath $errorLogFile
                $Result+=$ResultObject
            }

}
$result | Export-Csv "E:\Temp\RDS\Terminal_License_Server_Info_$dateTime.csv" -NoTypeInformation
