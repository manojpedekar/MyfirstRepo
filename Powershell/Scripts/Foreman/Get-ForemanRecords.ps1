<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
	 Created on:   	12/18/2024 9:54 AM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

# Base URL and Credentials
$baseUrl = "https://foreman.ssnc-corp.cloud/api"
$credential = Get-Credential

Function Encode-APIUsername {
    Param (
        [Parameter(Mandatory = $false)]
        [string]$Username = "saltforeman",
        [Parameter(Mandatory = $false)]
        [string]$Password = "7y7TC810J5YiJDXP8rvE2w"
    )
    
    $Credential = "$($Username):$($Password)"
    $EncodedCredential = [System.Text.Encoding]::UTF8.GetBytes($Credential)
    $EncodedCredential = [System.Convert]::ToBase64String($EncodedCredential)
    $AuthorizationHeader = "Basic $EncodedCredential"
    
    return $AuthorizationHeader
    
}

# Function to get all hosts
Function Get-AllHosts {
    Param (
        [int]$perPage = 100 
    )
    
    $Uri = "$baseUrl/hosts?per_page=$perPage&include=all_parameters"
    
    $Headers = @{
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
        "Authorization" = Encode-APIUsername
    }
    
    $response = Invoke-WebRequest -Method Get -Uri $Uri -Headers $Headers
    
    Return $response
   
}

# Function to get selected facts for a specific host
Function Get-FactsForHost ($hostname, $selectedFacts) {
    $url = "$baseUrl/hosts/$hostname/facts"
    $facts = Invoke-RestMethod -Uri $url -Authentication Basic -Credential $credential -Method Get
    $selectedData = @{ }
    ForEach ($fact In $selectedFacts) {
        If ($facts.psobject.properties.name -contains $fact) {
            $selectedData[$fact] = $facts.$fact
        }
    }
    Return $selectedData
}

Function Get-ForemanHostFacts {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$Hostname
    )
    
    $Headers = @{
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
        "Authorization" = Encode-APIUsername
    }
    
    $Uri = "https://foreman.ssnc-corp.cloud/api/hosts/$Hostname/facts?per_page=10000"
    $response = Invoke-WebRequest -Method Get -Uri $Uri -Headers $Headers
    
    Return $response
}

# Example of using the function
Get-ForemanHostFacts -Hostname "10-222-87-169.ssnc-corp.cloud"




# Main execution
$selectedFacts = @('os', 'uptime', 'ipaddress') # Specify the facts you want
$hosts = Get-AllHosts
$hostFacts = @{ }

ForEach ($host In $hosts) {
    $hostFacts[$host] = Get-FactsForHost -hostname $host -selectedFacts $selectedFacts
}

# Display the collected facts
$hostFacts



