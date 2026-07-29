function New-CloudAPIToken {
    <#
    .SYNOPSIS
        Creates a new API token for the current user.
    
    .DESCRIPTION
        Generates a new API token that can be used for programmatic access
        to the cloud platform. The token value is only displayed once upon
        creation and cannot be retrieved later. Store it securely!
    
    .PARAMETER Name
        A descriptive name for the API token. Required.
    
    .PARAMETER ExpiresDays
        Number of days until the token expires. If not specified, uses the
        default expiration period (typically 90 days).
    
    .EXAMPLE
        PS> New-CloudAPIToken -Name "CI/CD Pipeline"
        
        Creates a new API token with the default expiration.
    
    .EXAMPLE
        PS> New-CloudAPIToken -Name "Temporary Access" -ExpiresDays 7
        
        Creates a new API token that expires in 7 days.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
        IMPORTANT: The response will include the token value which should be
        immediately stored securely as it cannot be retrieved again.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
        
        WARNING: The token value is only returned once upon creation.
        Store it immediately in a secure location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 365)]
        [int]$ExpiresDays
    )
    
    try {
        # Build request body
        $body = @{
            name = $Name
        }
        
        if ($ExpiresDays) {
            $body['expiresInDays'] = $ExpiresDays
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'iam/tokens' -Method 'POST' -Headers $headers -Body $body
        
        # Display warning about token security
        Write-Warning "API Token created successfully! IMPORTANT: Store the token value securely as it cannot be retrieved again."
        
        return $response
    }
    catch {
        Write-Error "Failed to create API token: $($_.Exception.Message)"
        return $null
    }
}
