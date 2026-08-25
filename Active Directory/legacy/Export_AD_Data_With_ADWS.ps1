# Specify the domain or domain controller here
$DomainController = "ad.dstsystems.com"   # <-- change this as needed
# Query all servers from the specified AD domain and export to CSV with domain name and timestamp
Get-ADComputer -Server $DomainController `
    -Properties OperatingSystem, ServicePrincipalName, DNSHostName, IPv4Address, DistinguishedName `
    -LDAPFilter '(operatingsystem=*Server*)' |
Select-Object `
    Name, 
    OperatingSystem, 
    Enabled, 
    DNSHostName, 
    IPv4Address, 
    @{ 
        Name = 'ClusterObject'; 
        Expression = {
            # Safely check if serviceprincipalname contains MSClusterVirtualServer
            if ($_.ServicePrincipalName -and ($_.ServicePrincipalName -join '') -like '*MSClusterVirtualServer*') {
                $true
            } else {
                $false
            }
        } 
    },
    @{ 
        Name = 'OU';
        Expression = {
            # Extract only OU components from DistinguishedName and join with '/'
            if ($_.DistinguishedName) {
                ($_.DistinguishedName -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_ -replace '^OU=', '' }) -join '/'
            } else {
                ''
            }
        }
    } |
Export-CSV "C:\temp\$($DomainController.Replace('.', '_'))-clusterobjects-$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation -Encoding UTF8