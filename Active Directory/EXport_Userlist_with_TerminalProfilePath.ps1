$targetDomain = "globeop.com"
$results = New-Object System.Collections.Generic.List[PSObject]
$allUsers = Get-ADUser -Filter * -Server $targetDomain
foreach ($user in $allUsers) {
    try {
        $adsiPath = "LDAP://$targetDomain/$($user.DistinguishedName)"
        $adsiUser = [ADSI]$adsiPath

        $results.Add([PSCustomObject]@{
            SAMAccountName = $user.SamAccountName
            ProfilePath    = $(try { $adsiUser.psbase.InvokeGet("TerminalServicesProfilePath") } catch { $null })
            HomeDirectory  = $(try { $adsiUser.psbase.InvokeGet("TerminalServicesHomeDirectory") } catch { $null })
            HomeDrive      = $(try { $adsiUser.psbase.InvokeGet("TerminalServicesHomeDrive") } catch { $null })
            AllowLogon     = $(try { $adsiUser.psbase.InvokeGet("AllowLogon") } catch { $null })
        })
    }
    catch {
        Write-Warning "Could not read RDS data for $($user.SamAccountName)"
    }
}


$results | Out-GridView
Or
$results | Export-Csv -Path "C:\temp\AllUsersRDS.csv" -NoTypeInformation
