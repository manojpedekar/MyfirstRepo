<#
    .SYNOPSIS
        Opens TCP/3000 from a Resilio agent security group to the Resilio
        console tier. One-off network access rule.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed 2023-10-02 to open
        the Resilio agent->console path for SS&C deployment. Posted a single
        rule to the network-api v4 access_mgmt endpoint, which the Cloud-API
        module does not wrap (different API surface).

        Do not re-run without reviewing the hardcoded source/destination IDs
        and confirming the rule is still desired. The trailing Invoke-RestMethod
        on the ip/zones endpoint references an undefined $base64AuthInfo and
        was never functional - preserved as-is from the original.

        Originally also defined a Get-CloudCMDB helper that was never called;
        removed during reorg. The canonical Get-CloudCMDB now lives in the
        Cloud-API module.
#>

$body = @{
	action			   = "add"
	source			   = "securitygroup-beecb8ce-baf0-42de-a45b-4882f5b88188"
	source_tenant	   = "ssnc"
	destination	       = "tier-a096f065-1898-4876-8b21-e440a76d0536"
	destination_tenant = "ssnc"
	service_ports	   = "3000"
	protocol		   = "tcp"
	request		       = "add"
	requester		   = "Jeff Spenner"
	description	       = "Open ports for Resilio agents to console"
}

$bodyDouble = $body | ConvertTo-Json

$params = @{
	URi  = "https://network-api.ssnc-corp.cloud/api/v4/cloud/access_mgmt"
	
	Body = $bodyDouble
}

Invoke-RestMethod @params -Method Post -Headers $Header
Invoke-RestMethod -Method GET "https://network-api.ssnc-corp.cloud//api/v4/cloud/ip/zones?tenant=ssnc&ip=10.57.53.30&fqdn=mum1ctxprduk02.globeop.com" -Headers @{ Authorization = ("Basic {0}" -f $base64AuthInfo) }