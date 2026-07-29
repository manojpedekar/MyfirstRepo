function Set-CloudUser {
    <#
    .SYNOPSIS
        Updates an existing cloud user.
    
    .DESCRIPTION
        Updates the properties of an existing cloud user, including first name,
        last name, and project assignments.
    
    .PARAMETER Id
        The unique identifier of the user to update. Required.
    
    .PARAMETER FirstName
        The updated first name of the user.
    
    .PARAMETER LastName
        The updated last name of the user.
    
    .PARAMETER ProjectIds
        Array of project IDs to assign the user to. Replaces existing assignments.
    
    .EXAMPLE
        PS> Set-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a" -FirstName "Johnny"
        
        Updates the first name of the specified user.
    
    .EXAMPLE
        PS> Set-CloudUser -Id "user-55c319eb-5944-4d00-a927-02e2eff4430a" -ProjectIds @("project-1", "project-2")
        
        Updates the user's project assignments.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('UserId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$FirstName,
        
        [Parameter(Mandatory=$false)]
        [string]$LastName,
        
        [Parameter(Mandatory=$false)]
        [string[]]$ProjectIds
    )
    
    process {
        try {
            # Build request body with only provided parameters
            $body = @{}
            
            if ($PSBoundParameters.ContainsKey('FirstName')) {
                $body['firstName'] = $FirstName
            }
            
            if ($PSBoundParameters.ContainsKey('LastName')) {
                $body['lastName'] = $LastName
            }
            
            if ($PSBoundParameters.ContainsKey('ProjectIds')) {
                $body['projectIds'] = $ProjectIds
            }
            
            # Ensure we have at least one property to update
            if ($body.Count -eq 0) {
                Write-Error "At least one property (FirstName, LastName, or ProjectIds) must be specified for update"
                return $null
            }
            
            # Make API request
            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
            $response = Invoke-CloudAPIRequest -Path "iam/users/$Id" -Method 'PUT' -Headers $headers -Body $body
            
            return $response
        }
        catch {
            Write-Error "Failed to update user '$Id': $($_.Exception.Message)"
            return $null
        }
    }
}
