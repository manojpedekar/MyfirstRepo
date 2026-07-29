function Get-CloudAPIToken {
    <#
    .SYNOPSIS
        Retrieves API tokens for the current user.
    
    .DESCRIPTION
        Gets details about API tokens associated with the authenticated user.
        Can retrieve a specific token by ID or list all tokens.
    
    .PARAMETER Id
        The unique identifier of the API token to retrieve.
    
    .EXAMPLE
        PS> Get-CloudAPIToken
        
        Lists all API tokens for the current user.
    
    .EXAMPLE
        PS> Get-CloudAPIToken -Id "token-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Retrieves details for a specific API token.
    
    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
        
        Note: For security reasons, the actual token value is only returned
        when the token is first created and cannot be retrieved afterward.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TokenId')]
        [string]$Id
    )
    
    begin {
        $headers = New-CloudAPIHeaders
    }
    
    process {
        try {
            # Determine path
            if ($Id) {
                $path = "iam/tokens/$Id"
            } else {
                $path = "iam/tokens"
            }
            
            # Make API request
            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to retrieve API token(s): $($_.Exception.Message)"
            return $null
        }
    }
}
