# Bind to ADVENT domain DC explicitly
$Root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://YKTDC04.ADVENT.com/DC=ADVENT,DC=com")
$Searcher = New-Object System.DirectoryServices.DirectorySearcher($Root)
$Searcher.Filter = "(&(objectCategory=computer)(operatingSystem=*Server*))"
$Searcher.PageSize = 1000
$Searcher.PropertiesToLoad.AddRange(@("cn","dnshostname","operatingsystem","useraccountcontrol","serviceprincipalname")) | Out-Null

$Searcher.FindAll() | ForEach-Object {
    $uac = $_.Properties.useraccountcontrol[0]
    [PSCustomObject]@{
        Name = $_.Properties.cn[0]
        OperatingSystem = $_.Properties.operatingsystem[0]
        Enabled = -not ($uac -band 2)
        DNSHostName = $_.Properties.dnshostname[0]
        IPv4Address = $null
        ClusterObject = (($_.Properties.serviceprincipalname -join '') -like '*MSClusterVirtualServer*')
    }
} | Export-Csv C:\temp\ADVENT-servers-and-clusters.csv -NoTypeInformation -Encoding UTF8
