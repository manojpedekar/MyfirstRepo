<# 
.NOTES
	===========================================================================
	 Created with: 	Visual Studio Code
	 Updated on:   	12/12/2025
	 Created by:   	tnewnham
	 Organization: 	SS&C
	 Filename:      Get-AgentErrors.ps1
	===========================================================================

.DESCRIPTION
This script will query the specified Resilio management console for errors pertaining to all jobs then export to (what? csv,xml? Could maybe have IIS just publish the XML for view and we automate this call?)

What I want. 
URI parameter to make this work anywhere.
Gather all errors
  then get all data with get-fileerrors
Format that data and export to a format
possibly automate this and have IIS pull the file on load?

.EXAMPLE

@Params = @{ 
  Uri = "http://somesite.com:111/api/v2/.../..."
  APIKey = "#############################################"
  Outfile = "C:\some\place"
}

Get-AgentErrors.ps1 @Params

#>


# Parameter help description
Param (
[Parameter(Mandatory=$true,ValueFromPipeline)][string]$mgmthost,
[Parameter(ValueFromPipeline)][string]$Outfile
)


## Import APIKey
function Unprotect-String {
    param (
    [string]$StringtoDecrypt,
    [switch]$Computer
    )

    if ($Computer) {
        $key = "LocalMachine"
    } else {
        $key = "CurrentUser"
    }
    $data = [Convert]::FromBase64String($StringtoDecrypt)
    $data = [System.Security.Cryptography.ProtectedData]::Unprotect($data, $null, [System.Security.Cryptography.DataProtectionScope]::$key)
    [System.Text.Encoding]::UTF8.GetString($data)
}

$KeyFilePath = "C:\scripts\resilio\keyfile.key" 

if ((Test-Path $KeyFilePath) -eq $True) {
    $APIKey = Unprotect-String -Computer (Get-Content $KeyFilePath)
} else {
    $APIKey = Read-Host "To use this script, provide your Cloud API key"
}
# Finish Loading API Key


#Variables
$Uri = "https://$($mgmthost):8446/api/v2"


#Functions
Function Get-Agent {

    Param(
        [int]$agentId
    )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  if ($agentId) { $request = "$($Uri)/agents/$($agentId)?pretty=true" }
  else { $request = "$($Uri)/agents?pretty=true" } 
  
  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}

Function Get-FileErrors {
    
  Param(
    [int]$agentId,
    [int]$jobId,
    [string]$folderId,
    [string]$codestr
  )
  
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", "Token $($APIKey)") 
  $headers.Add("Content-Type", "application/json")

  $request = "$($Uri)/runs/$($jobId)/agents/$($agentId)/errors/files?folderid=$($folderId)&error_code=$($codestr)&max_entries=100" 

  $response = Invoke-RestMethod $request -Method "GET" -Headers $headers -SkipCertificateCheck

  Return $response
}


function Get-LockedFiles {

  $Agents = Get-Agent

  foreach ($agent in $Agents) {
    $errors = $agent | select -ExpandProperty errors
    $agentId = $agent | select -ExpandProperty Id 
    if ($null -eq $errors) {
    } else {
      foreach ($err in $errors) {
        $Param = @{
          agentId = $agentId
          jobId = $err.job_id
          folderId = $err.folderid
          codestr = $err.code_str
        }
        Get-FileErrors @Param
      }
    }
  }
}

## Execution
$LockedFiles = Get-LockedFiles

if ($Outfile) {
  $LockedFiles | Export-Clixml -Path $Outfile
} else {
  foreach ($file in $LockedFiles) {
    $driveletter = "$($file.path)\"
    $filepath = $file.files | select -ExpandProperty path
    foreach ($path in $filepath) {
      $driveletter + $path
    }
  }
}
