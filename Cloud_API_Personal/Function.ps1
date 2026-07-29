Function New-NetAccess {
    <#
 .SYNOPSIS
 This function creates access rules via the SS&C Cloud API.

 .DESCRIPTION
 Creates network access rules by invoking the SS&C Cloud API endpoint. Supports
 configuration via parameters, environment variables, or credential files for
 improved security and flexibility.

 .PARAMETER Name
 The name of the access rule to create.

 .PARAMETER Source
 The source security group ID or identifier.

 .PARAMETER SourceTenant
 The source tenant name.

 .PARAMETER Destination
 The destination security group ID or identifier.

 .PARAMETER DestinationTenant
 The destination tenant name.

 .PARAMETER Ports
 The port(s) to allow (e.g., "443" or "443,8443").

 .PARAMETER Protocol
 The protocol type: 'tcp' or 'udp'.

 .PARAMETER APIKey
 The SS&C Cloud API Key. If not provided, checks environment variable
 'SSNC_API_KEY' or prompts for user input.

 .PARAMETER APIEndpoint
 The API endpoint URL. Defaults to production endpoint if not specified.

 .EXAMPLE
 $Param = @{
     name = "New Access Rule on 443/tcp"
     source = "securitygroup-6bc70d2c-3e1e-4e59-9e1f-bb1a74d5711b"
     sourcetenant = "ssnc"
     destination = "securitygroup-8d38b3ea-c46f-434e-8c83-20e111b5d395"
     destinationTenant = "ssnc"
     protocol = "tcp"
     ports = "443"
 }
 New-NetAccess @Param -Verbose

    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Source,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SourceTenant,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Destination,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DestinationTenant,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Ports,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][ValidateSet('tcp','udp')][string]$Protocol,
        [Parameter(Mandatory=$false)][string]$APIKey,
        [Parameter(Mandatory=$false)][string]$APIEndpoint = "https://portal.ssnc-corp.cloud/api/v2/network/accesses"
    )

    Begin {
        Write-Verbose "Initializing New-NetAccess function..."
        
        # Resolve API Key from multiple sources
        if ([string]::IsNullOrEmpty($APIKey)) {
            Write-Verbose "APIKey parameter not provided, checking environment variable..."
            $APIKey = $env:SSNC_API_KEY
            
            if ([string]::IsNullOrEmpty($APIKey)) {
                Write-Verbose "No environment variable found, prompting user for API Key..."
                $APIKey = Read-Host "Please enter your SS&C Cloud API Key" -AsSecureString
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($APIKey)
                $APIKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
        }
        
        if ([string]::IsNullOrEmpty($APIKey)) {
            throw "API Key is required. Set SSNC_API_KEY environment variable or provide APIKey parameter."
        }
        
        Write-Verbose "API Endpoint: $APIEndpoint"
    }

    Process {
        try {
            Write-Verbose "Building request headers..."
            $headers = @{
                "x-api-key" = $APIKey
                "Content-Type" = "application/json"
                "accept" = "application/json"
            }

            Write-Verbose "Creating JSON payload for access rule: $Name"
            $jsondata = @{
                "name" =                 $Name
                "source" =               $Source
                "sourceTenant" =         $SourceTenant
                "destination" =          $Destination
                "destinationTenant" =    $DestinationTenant
                "ports" =                $Ports
                "protocol" =             $Protocol
            } | ConvertTo-Json

            Write-Verbose "Sending POST request to API endpoint..."
            Write-Verbose "Request body: $jsondata"

            try {
                $response = Invoke-RestMethod $APIEndpoint `
                    -Method 'Post' `
                    -Headers $headers `
                    -Body $jsondata `
                    -TimeoutSec 30 `
                    -ErrorAction Stop
            }
            catch {
                # Try to capture error response body for better debugging
                $errorResponse = $_.Exception.Response
                $statusCode = $errorResponse.StatusCode.value__
                
                try {
                    $stream = $errorResponse.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                    Write-Verbose "API Error Response Body: $responseBody"
                }
                catch {
                    $responseBody = "Could not read response body"
                }
                
                throw "API Error ($statusCode): $responseBody"
            }

            Write-Verbose "Response received: $(($response | ConvertTo-Json -Compress))"

            # Validate response
            if ($null -eq $response) {
                throw "API returned null response. Please verify the request parameters."
            }

            if ($response.status -eq 'error' -or $response.error) {
                throw "API Error: $($response.error -join '; ')"
            }

            Write-Verbose "Access rule created successfully."
            return $response.content
        }
        catch {
            Write-Error "Failed to create access rule: $_"
            throw
        }
    }

    End {
        Write-Verbose "New-NetAccess function completed."
    }
}

Function New-NetAccessBatch {
    <#
 .SYNOPSIS
 Imports network access rule definitions from JSON and creates them.

 .DESCRIPTION
 Reads a JSON file containing one or more access rule objects and invokes
 New-NetAccess for each entry. This is useful for bulk imports and repeatable
 configuration when network rule parameters change frequently.

 .PARAMETER JsonPath
 Path to the JSON file containing the rule definitions.

 .PARAMETER APIKey
 Optional API key to use for all requests. If omitted, each New-NetAccess call
 will resolve the key from environment or prompt as configured.

 .PARAMETER APIEndpoint
 Optional API endpoint to use for all requests.

 .PARAMETER ContinueOnError
 If specified, the function continues processing remaining rules after a failure.

 .EXAMPLE
 New-NetAccessBatch -JsonPath "C:\rules\NetworkRules.json" -Verbose

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$JsonPath,
        [Parameter(Mandatory=$false)][string]$APIKey,
        [Parameter(Mandatory=$false)][string]$APIEndpoint = "https://portal.ssnc-corp.cloud/api/v2/network/accesses",
        [Parameter(Mandatory=$false)][Switch]$ContinueOnError
    )

    Begin {
        if (-not (Test-Path -Path $JsonPath -PathType Leaf)) {
            throw "JSON file not found: $JsonPath"
        }

        Write-Verbose "Reading JSON file: $JsonPath"
        $rawJson = Get-Content -Path $JsonPath -Raw
        try {
            $parsedJson = $rawJson | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file '$JsonPath': $_"
        }

        if ($null -eq $parsedJson) {
            throw "JSON file '$JsonPath' is empty or invalid."
        }

        if ($parsedJson.PSObject.Properties.Name -contains 'rules') {
            $rules = $parsedJson.rules
        }
        else {
            $rules = $parsedJson
        }

        if ($null -eq $rules) {
            throw "No rule objects found in JSON file '$JsonPath'."
        }

        if ($rules -is [System.Collections.IEnumerable] -and $rules -isnot [string]) {
            $ruleList = @($rules)
        }
        else {
            $ruleList = @($rules)
        }

        if ($ruleList.Count -eq 0) {
            throw "JSON file '$JsonPath' contains no rule entries."
        }

        Write-Verbose "Loaded $($ruleList.Count) rule(s) from JSON."
    }

    Process {
        foreach ($rule in $ruleList) {
            $ruleName = $rule.name
            if ([string]::IsNullOrEmpty($ruleName)) {
                $ruleName = "Unnamed rule"
            }

            Write-Verbose "Processing rule: $ruleName"

            $parameters = @{
                Name = $rule.name
                Source = $rule.source
                SourceTenant = $rule.sourceTenant
                Destination = $rule.destination
                DestinationTenant = $rule.destinationTenant
                Ports = $rule.ports
                Protocol = $rule.protocol
                APIKey = $APIKey
                APIEndpoint = $APIEndpoint
            }

            if ($PSCmdlet.ShouldProcess($ruleName, 'Create access rule')) {
                try {
                    if ($PSBoundParameters.ContainsKey('Verbose')) {
                        New-NetAccess @parameters -Verbose
                    }
                    else {
                        New-NetAccess @parameters
                    }
                    Write-Verbose "Successfully created rule: $ruleName"
                }
                catch {
                    Write-Error "Failed to create rule '$ruleName': $_"
                    if (-not $ContinueOnError) {
                        throw
                    }
                }
            }
        }
    }

    End {
        Write-Verbose "New-NetAccessBatch completed."
    }
}