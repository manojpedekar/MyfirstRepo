<#
    FROZEN HISTORICAL RECORD. One-off trojan-footprint scanner from the
    Install-MSIPackage folder, miscategorized there because it shared the
    serverlist.txt pattern with the FireEye install scripts. Renamed from
    get-remotepathcheck.ps1.

    What it does: walks .\serverlist.txt, checks each target for the
    presence of \\<server>\c$\programdata\windnt\ and the file
    conhost.exe within it. If both exist, the host is flagged.

    The "windnt" path + conhost.exe filename were used by a specific
    malware family in 2021-era incidents; this script enumerated which
    hosts in the fleet were affected. Kept as a reference pattern.
#>

$serverlist = get-content .\serverlist.txt

Foreach ($server in $serverlist) {
	$targetpath = "\\" + $server + "\c$\programdata\windnt"
	If ((Test-Path $targetpath) -eq $true) {
		Write-Host "Troject path detected on" $server
		$filechecked = $targetpath + "\conhost.exe"
		If ((Test-Path $filechecked) -eq $true) {
			Write-Host "Trojan file detected on" $server
		} else {
            Write-Host "Trojan file not found on" $server
        }
	} else {
        Write-Host "Trojan path not found on " $server
    }
}