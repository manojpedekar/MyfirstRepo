# Define the group name
$GroupName = "SSNC_Windt132kgroup"

# Get recursive members, filter for users, and select specific identity details
Get-ADGroupMember -server globeop.com -Identity $GroupName -Recursive | 
    Where-Object { $_.objectClass -eq "user" } | 
    Get-ADUser -Properties GivenName, Surname | 
    Select-Object @{Name="Username"; Expression={$_.SamAccountName}}, 
                  @{Name="First Name"; Expression={$_.GivenName}}, 
                  @{Name="Last Name"; Expression={$_.Surname}} |
    Export-Csv -Path "C:\Temp\SSNC_Windt132kgroup_UserList.csv" -NoTypeInformation


