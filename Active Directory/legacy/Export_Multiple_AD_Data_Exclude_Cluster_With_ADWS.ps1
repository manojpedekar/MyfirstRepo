# List your domains here
$domains = @(
"sscclientiim.ssncad.global"
"ifdsgroup.co.uk"
"Globeop.com"
"Cloudad.ssncad.global"
"ssnc-corp.global"
"spla.ssncad.global"
)

$results = foreach ($domain in $domains) {

    Get-ADComputer -Server $domain `
        -Properties DNSHostName, IPv4Address, OperatingSystem, servicePrincipalName `
        -LDAPFilter '(operatingsystem=*Server*)' |

        # Add DomainName as first column
        Select-Object `
            @{l='DomainName'; e={ $domain }},
            Name,
            DNSHostName,
            IPv4Address,
            OperatingSystem,
            Enabled,
            @{l='IsClusterObject'; e={
                # Used only for filtering, NOT included in output
                if (($_.servicePrincipalName -join '') -like '*MSClusterVirtualServer*') {
                    $true
                } else {
                    $false
                }
            }}
}

# Exclude cluster objects and remove the helper property from output
$results | Where-Object { $_.IsClusterObject -eq $false } | Select-Object DomainName, Name, DNSHostName, IPv4Address, OperatingSystem, Enabled |  Export-Csv "C:\temp\MultiDomain_AD_Objects_Exclude_Cluster_$timestamp.csv" -NoTypeInformation -Encoding UTF8

