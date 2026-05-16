<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	5/29/2024 1:58 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	Get-LocalMachineCertData
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

#Subject Name

$IgnoreIssuers = @('CN=Cloudbase-Init WinRM')

$CertData = [System.Collections.ArrayList]@()
$certs = Get-ChildItem  Cert:\LocalMachine\my | ? {$_.Issuer -notin $IgnoreIssuers}

ForEach ($cert In $certs) {
	$CertData += [PSCustomObject]@{
		SubjectName  = $cert.Subject
		CommonName   = ($_.Subject -split ',')[0].Split('=')[1] 
		Issuer	     = $cert.Issuer
		SerialNumber = $cert.SerialNumber
		FriendlyName = $cert.FriendlyName
		NotAfter     = $cert.NotAfter
		NotBefore    = $cert.NotBefore
		Thumbprint   = $cert.Thumbprint
	}
	
}

$CertData


