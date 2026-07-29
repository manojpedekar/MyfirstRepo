function Get-CloudOrganization {
    <#
    .SYNOPSIS
        Retrieves organizations from the SS&C Cloud API.

    .DESCRIPTION
        Gets one or more organizations with optional filtering by ID or name.
        Organizations represent organizational units within a tenant.

    .PARAMETER Id
        The unique identifier of the organization to retrieve.

    .PARAMETER Name
        Filter organizations by name (supports partial matching).

    .PARAMETER TenantId
        Filter organizations by parent tenant ID.

    .EXAMPLE
        PS> Get-CloudOrganization

        Retrieves all organizations accessible to the current user.

    .EXAMPLE
        PS> Get-CloudOrganization -Id "org-12345"

        Retrieves a specific organization by ID.

    .EXAMPLE
        PS> Get-CloudOrganization -TenantId "tenant-12345"

        Retrieves all organizations under a specific tenant.

    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('OrganizationId')]
        [string]$Id,

        [Parameter(Mandatory=$false)]
        [string]$Name,

        [Parameter(Mandatory=$false)]
        [string]$TenantId
    )

    begin {
        $headers = New-CloudAPIHeaders
    }

    process {
        try {
            # Build query parameters
            $queryParams = @{
                sort = 'name,asc'
            }

            if ($Name) { $queryParams['name'] = $Name }
            if ($TenantId) { $queryParams['tenantId'] = $TenantId }

            # Determine path based on whether Id is provided
            $path = if ($Id) { "admin/organizations/$Id" } else { 'admin/organizations' }

            Write-Verbose "Retrieving organization(s) from path: $path"

            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams

            return $response
        }
        catch {
            Write-Error "Failed to retrieve organization(s): $($_.Exception.Message)"
            return $null
        }
    }
}
