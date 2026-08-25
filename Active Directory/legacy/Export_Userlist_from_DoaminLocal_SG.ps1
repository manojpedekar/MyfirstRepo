# 1. Target the DC for Domain C (where the group lives)
$GroupServer = "ssnc.global"

# 2. Target the Global Catalog (to find users from any domain in the forest)
$GCServer = "ssnc.global:3268"

$GroupName = "WINDT132K_Share_W"

# Get the group, grab the 'member' list, and process each member
Get-ADGroup -Identity $GroupName -Server $GroupServer -Properties Member | 
    Select-Object -ExpandProperty Member | 
    Get-ADUser -Server $GCServer -Properties GivenName, Surname | 
    Select-Object @{Name="Username"; Expression={$_.SamAccountName}}, 
                  @{Name="First Name"; Expression={$_.GivenName}}, 
                  @{Name="Last Name"; Expression={$_.Surname}} |
    Export-Csv -Path "C:\Temp\WINDT132K_Share_W_UserList.csv" -NoTypeInformation