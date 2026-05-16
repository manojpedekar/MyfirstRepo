<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	11/28/2022 9:03 AM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

$Domains = @('cloudad.ssncad.global',
	'admgmt.ssncad.global',
	'ad.dstsystems.com',
	'sscdirect.com',
	'spla.ssncad.global',
	'ssnc-corp.global',
	'-unknown-',
	'dstinet2.ad.he2.dstcorp.net',
	'fundrunner.local',
	'globeop.com',
	'adres.ssncad.global',
	'advent.com',
	'archive.global',
	'benefitsxml.com',
	'bfds.com',
	'bos.priv.evarenet.com',
	'ssnc.global',
	'bostonfinancial.biz',
	'BOSTONFINREMOTE.COM',
	'cbafacman.sscgateway.com',
	'cloud.advent',
	'sscclient01.ssncad.global',
	'corp.vardentech.com',
	'corp.vardentech.om',
	'dev.ad.testdev.dstcorp.net',
	'dev2k22.local',
	'devad.ad.dstcorp.net',
	'devad.ssnc-corp.global',
	'devext.ssncad.global',
	'devext.ssnc-corp.global',
	'devres.ssnc-corp.global',
	'dmz.evarenet.com',
	'dmzqa.fw.evare.com',
	'dsths.ad.dstcorp.net',
	'dstinet.ad.he3.dstcorp.net',
	'dstinet1.ad.he1.dstcorp.net',
	'DVI.COM',
	'eng.evare.local',
	'engbe.evare.local',
	'engdmz.evare.local',
	'evare.local',
	'evolvsuite.local',
	'extad.ssncad.global',
	'external.ad.dstsystems.com',
	'external.bostonfinancial.biz',
	'extranet.bostonfinancial.biz',
	'illuminatics.local',
	'int.ad.dstsystems.com',
	'tech.newkirk.com',
	'goares.com',
	'gocn.com',
	'HedgemetrixLLC.local',
	'hostedskyline.local',
	'hosting.cloud.advent',
	'iamdev.ad.dstcorp.net',
	'iamv8devtest.global',
	'iimdev.local',
	'iimssc.com',
	'its.labs.fmccorp.info',
	'labs.fmccorp.info',
	'lightning.sscgateway.com',
	'melbportia.local',
	'melbtest.isolated',
	'mgmt.evare.local',
	'mgmt.sscgateway.com',
	'outsourcing.fmco.com',
	'PORTIAHOSTING.com',
	'Posh.Test.Com',
	'Prime.Management',
	'priv.evarenet.com',
	'prod.fmco.com',
	'prodops.evare.local',
	'qadb2.evare.com',
	'rg2k19.devlocal',
	'salentica.com',
	'spla.ssnc-corp.global',
	'sprod.fmco.com',
	'sscclient02.ssncad.global',
	'sscdemo123.ssncad.global',
	'SSNCWEB.COM',
	'ssnctest.ssncad.global',
	'ssctechfs.global',
	'suitesolution.fmco.com',
	'swift.sscgateway.com',
	'test.dstsystems.com',
	'testad.ssnc-corp.global',
	'testext.ssnc-corp.global',
	'testing2008.ssncad.global',
	'testres.ssncad.global',
	'uatbe.evaretest.local',
	'uatdmz.evaretest.local',
	'VARDEN',
	'vpn.fmco.com',
	'web.fmco.com',
	'wm.sscgateway.com',
	'zoologic.net'
)

$KMS = @()

foreach ($Domain in $Domains)
{
	$KMS += Resolve-DnsName -Type SRV -Name _vlmcs._tcp.$Domain -ErrorAction SilentlyContinue
}

$KMS | ? { $_.QueryType -eq "SRV" }

