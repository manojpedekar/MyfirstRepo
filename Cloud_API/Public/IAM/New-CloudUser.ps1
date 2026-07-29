function New-CloudUser {
    <#
    .SYNOPSIS
        Creates a new user in the cloud IAM system.
    
    .DESCRIPTION
        Creates a new cloud user with the specified email address and optional
        first name, last name, and project assignments.
    
    .PARAMETER Email
        The email address for the new user. Required.
    
    .PARAMETER FirstName
        The first name of the user.
    
    .PARAMETER LastName
        The last name of the user.
    
    .PARAMETER ProjectIds
        Array of project IDs to assign the user to.
    
    .PARAMETER Wait
        If specified, waits for the user creation to complete.
    
    .PARAMETER Async
        If specified, returns immediately after making the request without waiting.
    
    .EXAMPLE
        PS> New-CloudUser -Email "newuser@example.com" -FirstName "John" -LastName "Doe"
        
        Creates a new user with the specified email and name.
    
    .EXAMPLE
        PS> New-CloudUser -Email "newuser@example.com" -ProjectIds @("project-1", "project-2") -Wait
        
        Creates a new user and assigns them to multiple projects, waiting for completion.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
        [string]$Email,
        
        [Parameter(Mandatory=$false)]
        [string]$FirstName,
        
        [Parameter(Mandatory=$false)]
        [string]$LastName,
        
        [Parameter(Mandatory=$false)]
        [string[]]$ProjectIds,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wait,
        
        [Parameter(Mandatory=$false)]
        [switch]$Async
    )
    
    try {
        # Build request body
        $body = @{
            email = $Email
        }
        
        if ($FirstName) {
            $body['firstName'] = $FirstName
        }
        
        if ($LastName) {
            $body['lastName'] = $LastName
        }
        
        if ($ProjectIds -and $ProjectIds.Count -gt 0) {
            $body['projectIds'] = $ProjectIds
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path 'iam/users' -Method 'POST' -Headers $headers -Body $body -Wait:$Wait -Async:$Async
        
        return $response
    }
    catch {
        Write-Error -Message "Failed to create user: $($_.Exception.Message)" -ErrorId 'NewCloudUserFailed'
        return $null
    }
}
