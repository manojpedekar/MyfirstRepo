# Powershell Module to be used to work with Resilio Management console and Agents. 
# This is a work in progress and items may not work as expected. 

#Get User API Token
$APIKey = "GPZNAFZPBH737QLRBIXL76HCACHNJX56YXPELFF5BX3XX654D5PA"
#$APIKey = Read-Host "To use this tool, please enter your Resilio API Token"

#Incorporate Protect-String and Unprotect-String for API key's and automated use. Encrypt with Machine credentials.

# Job Functions

Function Get-Job {
  
  Param(
      [int]$Id
  )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  if ($Id) { $request = "https://100-98-8-21:8446/api/v2/jobs/$($Id)?pretty=true" }
  else { $request = "https://100-98-8-21:8446/api/v2/jobs?pretty=true" } 
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}

Function New-Job {
  
  # 

  Param(
      [string]$name,
      [string]$description,
      [string]$type,

  )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  if (!$jobId) { $request = "https://100-98-8-21:8446/api/v2/jobs?pretty=true" }
  else { $request = "https://100-98-8-21:8446/api/v2/jobs/$($jobId)?pretty=true" } 
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}


Function Get-Info {
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  $request = "https://100-98-8-21:8446/api/v2/info"
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}

Function Get-Agent {

    Param(
        [int]$agentId
    )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  if ($agentId) { $request = "https://100-98-8-21:8446/api/v2/agents/$($agentId)?pretty=true" }
  else { $request = "https://100-98-8-21:8446/api/v2/agents?pretty=true" } 
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}

Function Get-License {
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  $request = "https://100-98-8-21:8446/api/v2/license/packages"
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}



Function Get-AgentProfile {
    
  Param(
    [string]$profileId
  )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  if (!$profileId) { $request = "https://100-98-8-21:8446/api/v2/agent_profiles?pretty=true" }
  else { $request = "https://100-98-8-21:8446/api/v2/agent_profiles/$($profileId)?pretty=true" } 
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}



Function Get-FileLocks {
    
  Param(
    [string]$jobId
  )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  $request = "https://100-98-8-21:8446/api/v2/runs/$($jobId)/file_locks?pretty=true" 
  
  $response = Invoke-RestMethod $request -Method "POST" -Headers $headers -SkipCertificateCheck

  Return $response
}

Function Get-FileErrors {
    
  Param(
    [int]$agentId,
    [int]$jobId
  )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  $request = "https://100-98-8-21:8446/api/v2/runs/$($jobId)/agents/$($agentId)/errors/files?pretty=true" 
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}

# Need to get 'folderId' from 

folderid=$($folderId)&error_code=$($errorcode)?