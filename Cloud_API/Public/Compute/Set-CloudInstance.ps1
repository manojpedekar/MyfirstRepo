function Set-CloudInstance {
    <#
    .SYNOPSIS
        Modifies properties of an existing cloud instance.
    
    .DESCRIPTION
        Updates the configuration of an existing cloud instance. Properties that are
        not specified will retain their current values. Can modify CPU, memory, name,
        patching group, backup policy, and enterprise flags.
    
    .PARAMETER Id
        The unique identifier of the instance to modify. Required.
    
    .PARAMETER Name
        The new name for the instance.
    
    .PARAMETER Cpu
        The new number of CPU cores.
    
    .PARAMETER Memory
        The new amount of memory in GB.
    
    .PARAMETER PatchingGroup
        The new patching group for the instance.
    
    .PARAMETER BackupPolicy
        The new backup policy for the instance.
    
    .PARAMETER MarkAsEnterpriseDatabase
        Flag to mark the instance as an enterprise database.
    
    .PARAMETER MarkAsEnterpriseCluster
        Flag to mark the instance as an enterprise cluster.
    
    .EXAMPLE
        PS> Set-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Cpu 8 -Memory 16
        
        Updates the instance to have 8 CPU cores and 16 GB of memory.
    
    .EXAMPLE
        PS> Set-CloudInstance -Id "i-55c319eb-5944-4d00-a927-02e2eff4430a" -Name "NewServerName"
        
        Renames the instance.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('InstanceId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [string]$Name,
        
        [Parameter(Mandatory=$false)]
        [int]$Cpu,
        
        [Parameter(Mandatory=$false)]
        [int]$Memory,
        
        [Parameter(Mandatory=$false)]
        [string]$PatchingGroup,
        
        [Parameter(Mandatory=$false)]
        [string]$BackupPolicy,
        
        [Parameter(Mandatory=$false)]
        [string]$MarkAsEnterpriseDatabase,
        
        [Parameter(Mandatory=$false)]
        [string]$MarkAsEnterpriseCluster
    )
    
    try {
        # Get current instance details to fill in unspecified parameters
        $current = Get-CloudInstance -Id $Id
        if (-not $current) {
            Write-Error "Instance '$Id' not found"
            return $null
        }
        
        # Use current values if not specified
        if (-not $PSBoundParameters.ContainsKey('Name')) { $Name = $current.name }
        if (-not $PSBoundParameters.ContainsKey('Cpu')) { $Cpu = $current.cpu }
        if (-not $PSBoundParameters.ContainsKey('Memory')) { $Memory = $current.memory }
        if (-not $PSBoundParameters.ContainsKey('PatchingGroup')) { $PatchingGroup = $current.patchingGroup }
        if (-not $PSBoundParameters.ContainsKey('BackupPolicy')) { $BackupPolicy = $current.backupPolicy }
        if (-not $PSBoundParameters.ContainsKey('MarkAsEnterpriseDatabase')) { $MarkAsEnterpriseDatabase = $current.enterpriseDatabase }
        if (-not $PSBoundParameters.ContainsKey('MarkAsEnterpriseCluster')) { $MarkAsEnterpriseCluster = $current.enterpriseCluster }
        
        # Build request body
        $body = @{
            name = $Name
            cpu = $Cpu
            memory = $Memory
            patchingGroup = $PatchingGroup
            backupPolicy = $BackupPolicy
            markAsEnterpriseDatabase = $MarkAsEnterpriseDatabase
            markAsEnterpriseCluster = $MarkAsEnterpriseCluster
            antiAffinity = "ERRORED"
        }
        
        # Confirm action
        if (-not $PSCmdlet.ShouldProcess("instance '$($current.name)' ($Id)", 'Update')) {
            return $null
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        $response = Invoke-CloudAPIRequest -Path "compute/instances/$Id" -Method 'PUT' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to update instance: $($_.Exception.Message)"
        return $null
    }
}
