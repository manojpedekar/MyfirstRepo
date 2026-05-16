<#
    .SYNOPSIS
        Inventories user home-drive folders across multiple fileservers,
        cross-references the folder names against AD users (resolving SIDs
        and cross-domain trusts), and flags candidates for deletion.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed 2022 as part of the
        home-drive cleanup effort. Scans hardcoded paths (E:\homedirs,
        G:\homedirs2, K:\homedirs, K:\homedirs3, L:\OLD_HomeDirs) on the
        fileserver where it runs, builds per-folder records with ACLs,
        sizes, last-modified times, then resolves each folder name back
        to an AD user across 17 trusted domains. The output (HomeDirResults.csv)
        flagged folders for the cleanup pass.

        Two notable behaviors:
          - L:\OLD_HomeDirs\* and folders matching '*Termed*' are auto-marked
            DeleteHomeDir = true.
          - Folders with zero non-inherited ACLs are auto-marked for
            deletion.
          - Folders whose ACLs contain a SID from a trusted domain trigger
            a per-domain Get-ADUser lookup; LegalHold OUs are preserved.

        Replaces an earlier version of the same script that handled fewer
        edge cases (only one ACL per folder, no LegalHold awareness).

        Do not re-run without confirming the hardcoded HomeDirs paths, the
        domain list, and the output CSV destination.
#>

#run on fileserver
Measure-Command {
	$HomeDirs = @('E:\homedirs',
		'G:\homedirs2',
		'K:\homedirs',
		'K:\homedirs3',
		'L:\OLD_HomeDirs')
	
	Remove-Variable DirInfo -ErrorAction SilentlyContinue
	
	foreach ($homeDir in $HomeDirs)
	{
		#build a list of the folders and the ACL's
		# Inherited Rights are excluded from the ACL List
		# System rights are excluded from the ACL list
		$DirInfo += dir $homedir -directory | select name, fullname,
													 @{ N = 'ACL'; e = { Get-Acl $_.fullname | select -expand access | ? { $_.IsInherited -eq $false -and $_.IdentityReference -notlike "*perm*" -and $_.IdentityReference -notlike "BUILTIN*" -and $_.IdentityReference -notlike "NT AUTHORITY*" -and $_.IdentityReference -notlike "CREATOR OWNER" } } },
													 @{ N = 'ACLCount'; e = { (Get-Acl $_.fullname | select -expand access | ? { $_.IsInherited -eq $false -and $_.IdentityReference -notlike "*perm*" -and $_.IdentityReference -notlike "BUILTIN*" -and $_.IdentityReference -notlike "NT AUTHORITY*" }).count } },
													 @{ N = 'SizeMB'; e = { [math]::round((Get-Childitem -Path $_.fullname -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum /1MB, 2) } },
													 @{ N = 'LastModifiedDate'; E = { (dir $_.fullname -Recurse -File | sort lastwritetime | select -last 1).lastwritetime } }
	}
	Export-Clixml -Path C:\temp\DirInfo.xml -InputObject $DirInfo
}

$domainSuffix = @(
	'ad.dstsystems.com'
	 ,'admgmt.ssncad.global'
	 ,'bostonfinancial.biz'
	 ,'BOSTONFINREMOTE.COM'
	 ,'dev.ad.testdev.dstcorp.net'
	 ,'dsths.ad.dstcorp.net'
	 ,'dstinet.ad.he3.dstcorp.net'
	 ,'dstinet1.ad.he1.dstcorp.net'
	 ,'dstinet2.ad.he2.dstcorp.net'
	 ,'external.ad.dstsystems.com'
	 ,'external.bostonfinancial.biz'
	 ,'extranet.bostonfinancial.biz'
	 ,'globeop.com'
	 ,'gocn.com'
	 ,'int.ad.dstsystems.com'
	 ,'ssnc.global'
	 ,'ssnc-corp.global'
)
$DomainSids = @()


foreach ($suffix in $domainSuffix)
{
	Remove-Variable DSID -ErrorAction SilentlyContinue
	try { $DSID = Get-ADDomain -Server $suffix }
	catch { Write-Host "$($suffix) is not reachable" }
	if ($DSID) { $DomainSids += $DSID }
}

$DirInfo = Import-Clixml -Path C:\temp\DirInfo.xml
$DirInfo = $DirInfo | select *, ADAccount, Domains, DeleteHomeDir, Identities, UserPrincipalName

foreach ($record in $DirInfo) {
	$FoundUser = "FALSE"
	$SIDDomains = @()
	$UserUPN = @()
	$DeleteHomeDir = $null
	
	if ($record.fullname -like "L:\OLD_HomeDirs\*" -or $record.fullname -like '*Termed*') { $DeleteHomeDir = $true }
	if ($record.aclcount -eq 0) { $DeleteHomeDir = $true }
	if ($record.aclcount -gt 0) { $record.Identities = ($record.ACL.IdentityReference.value | Select-Object -unique) -join ',' }
	if ($record.acl.IdentityReference -like "*\*") { $FoundUser = "TRUE"; $DeleteHomeDir = $false }
		
	if ($record.aclcount -gt 0)
	{
		foreach ($UserSid in ($record.acl))
		{
			Remove-Variable tmpSIDDomains -ErrorAction SilentlyContinue
			if ($UserSid.IdentityReference -like "S-1*") { $tmpSIDDomains = ($DomainSids | ? { $_.DomainSID -eq $UserSid.IdentityReference.AccountDomainSid }).dnsroot }
			if ($UserSid.IdentityReference -like "*\*") { $tmpSIDDomains = ($DomainSids | ? { $_.NetBIOSName -eq $UserSid.IdentityReference.value.split("\")[0] }).dnsroot }
			if ($tmpSIDDomains) { $SIDDomains += $tmpSIDDomains }
			if ((-not $tmpSIDDomains) -and ($usersid.IdentityReference.tostring() -ne "CREATOR OWNER")) { try { $SIDDomains += $UserSid.IdentityReference.AccountDomainSid.tostring() } catch{ Write-Host $record } }
		}
	}
	
	#we need to add a loop for each acl
	
	if ($SIDDomains.length -gt 0)
	{
		$NamedDomains = $SIDDomains | ? { $_ -notlike "S-1*" } | select -Unique
		foreach ($NamedDomain in $NamedDomains)
		{
			try
			{
				$ADUser = get-aduser $record.name -Properties HomeDirectory -Server $NamedDomain
				$UserUPN +=$ADUser.UserPrincipalName
				if ($ADUser.enabled) { $FoundUser = "TRUE" } else { $FoundUser = "Disabled" }
				$DeleteHomeDir = $false
				if ($ADUser.DistinguishedName.contains("LegalHold")) { $FoundUser = "LegalHold" }
			}
			catch { }
		}
	} else {
		try
		{
			$ADUser = get-aduser $record.name -Properties HomeDirectory -Server ad.dstsystems.com
			$UserUPN += $ADUser.UserPrincipalName
			if ($ADUser.enabled) { $FoundUser = "TRUE" } else { $FoundUser = "Disabled" }
			$DeleteHomeDir = $false
			if ($ADUser.DistinguishedName.contains("LegalHold")) { $FoundUser = "LegalHold" }
		}
		catch { }	
	}
	
	
	$record.Domains = ($SIDDomains | select -unique) -join ','
		
	#if ($FoundUser -eq "FALSE" -and $record.domains -eq "ad.dstsystems.com" -and $DeleteHomeDir -eq $null){ $DeleteHomeDir = $true}

	$record.UserPrincipalName = ($UserUPN | select -unique) -join ','
	$record.ADAccount = $FoundUser
	$record.DeleteHomeDir = $DeleteHomeDir
	
}

#post processing update rules
$DirInfo | ? { $_.adaccount -eq "false" -and $_.deletehomedir -eq $null } | % { $_.deletehomedir = $true }

