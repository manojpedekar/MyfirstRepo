Function Add-FSACE {
<#
    .SYNOPSIS
        Adds a filesystem ACE to a folder for the specified domain group at
        one of four standard access levels.

    .DESCRIPTION
        Grants a domain group access on a folder using one of four common
        permission profiles:

          RO       ReadAndExecute
          M        Modify
          RW       Modify + DeleteSubdirectoriesAndFiles
          FC       FullControl

        The ACE is added with ContainerInherit + ObjectInherit so it applies
        to the folder and all descendants.

        Note the difference between M (Modify only) and RW (Modify plus the
        DeleteSubdirectoriesAndFiles special permission). RW allows deleting
        child items even when the user lacks Delete on them individually -
        useful for janitor-style cleanup. M does not include that capability.

    .PARAMETER Path
        The folder to update.

    .PARAMETER DomainGroup
        The DOMAIN\group identity to grant.

    .PARAMETER Access
        One of RO, M, RW, FC.

    .EXAMPLE
        Add-FSACE -Path "E:\share\Reports" -DomainGroup "GLOBEOP\reports-readers" -Access RO

    .EXAMPLE
        Add-FSACE -Path "E:\share\Drop" -DomainGroup "GLOBEOP\drop-writers" -Access M
#>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$DomainGroup,
        [Parameter(Mandatory = $true)]
        [ValidateSet('RO', 'M', 'RW', 'FC')]
        [string]$Access
    )

    # Ensure the folder exists
    If (-not (Test-Path -Path $Path)) {
        Write-Error "The path '$Path' does not exist."
        Return
    }

    Try {
        # Get current ACL
        $acl = Get-Acl -Path $Path

        # Define rights
        Switch ($Access) {
            'RO' {
                $rights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
            }
            'M' {
                $rights = [System.Security.AccessControl.FileSystemRights]::Modify
            }
            'RW' {
                $rights = [System.Security.AccessControl.FileSystemRights]::Modify -bor `
                    [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
            }
            'FC' {
                $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
            }
        }

        # Create inheritance/propagation flags
        $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None

        # Create new access rule
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule (
            $DomainGroup,
            $rights,
            $inheritanceFlags,
            $propagationFlags,
            [System.Security.AccessControl.AccessControlType]::Allow
        )

        # Add the new rule
        $acl.AddAccessRule($accessRule)

        # Apply the updated ACL
        Set-Acl -Path $Path -AclObject $acl

        Write-Host "ACE successfully added for '$DomainGroup' on '$Path' ($Access)" -ForegroundColor Green
    } Catch {
        Write-Error "Failed to apply ACE: $_"
    }
}
