function Get-CloudTenant {
    <#
    .SYNOPSIS
        Retrieves tenants from the SS&C Cloud API.

    .DESCRIPTION
        Gets one or more tenants with optional filtering by ID or name.
        Tenants represent top-level organizational boundaries in the cloud platform.

    .PARAMETER Id
        The unique identifier of the tenant to retrieve.

    .PARAMETER Name
        Filter tenants by name (supports partial matching).

    .EXAMPLE
        PS> Get-CloudTenant

        Retrieves all tenants accessible to the current user.

    .EXAMPLE
        PS> Get-CloudTenant -Id "tenant-12345"

        Retrieves a specific tenant by ID.

    .EXAMPLE
        PS> Get-CloudTenant -Name "Production"

        Retrieves tenants matching the name "Production".

    .OUTPUTS
        PSCustomObject or Array of PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('TenantId')]
        [string]$Id,

        [Parameter(Mandatory=$false)]
        [string]$Name
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

            # Determine path based on whether Id is provided
            $path = if ($Id) { "admin/tenants/$Id" } else { 'admin/tenants' }

            Write-Verbose "Retrieving tenant(s) from path: $path"

            $response = Invoke-CloudAPIRequest -Path $path -Method 'GET' -Headers $headers -QueryParameters $queryParams

            return $response
        }
        catch {
            Write-Error "Failed to retrieve tenant(s): $($_.Exception.Message)"
            return $null
        }
    }
}
