<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	10/28/2025 1:53 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>



[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $true, HelpMessage = 'Enter computer name or pattern to check DNS record(s) for')]
    [string]$computername,
    [Parameter(Mandatory = $false, HelpMessage = 'Whether to fix issues found (True or False)')]
    [bool]$fixParameter = $false
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

Import-Module -Name ActiveDirectory -ErrorAction Stop -Verbose:$false

[string[]]$reservedNames = @('DomainDnsZones', 'ForestDnsZones', '@')
[int]$fixedCount = 0
$thisDomain = Get-ADDomain
[string]$DomainName = $thisDomain.DNSroot
[string]$AdIntegrationType = 'Domain'
[string]$DomainDn = $thisDomain.DistinguishedName

## get domain controllers so we can avoid lest we break anything big style
[hashtable]$domainControllers = @{ }
$domainControllers = @{ }
ForEach ($dc In Get-ADGroupMember -Identity 'Domain Controllers') {
    $domainControllers[$dc.DistinguishedName] = $dc.SID
}

[string]$adpath = "AD:\DC=$DomainName,CN=MicrosoftDNS,DC=$AdIntegrationType`DnsZones,$DomainDn"

Write-Verbose "AD path is `"$adpath`""
