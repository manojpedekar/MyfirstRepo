Function Add-DeleteSubdirectoriesAndFilesACE {
<#
    .SYNOPSIS
        Adds an ACE granting a domain group the DeleteSubdirectoriesAndFiles
        + ReadExtendedAttributes + Synchronize special permissions on a
        folder.

    .DESCRIPTION
        Grants the named domain group the ability to delete child files
        and subfolders even when the group does not have explicit Delete
        rights on each child. Common use case: a janitor / cleanup service
        account that needs to remove user-owned content under a shared root
        without inheriting full Modify rights to the individual files.

        The ACE is added with ContainerInherit + ObjectInherit and no
        propagation flags, so it applies to the folder and all descendants.

    .PARAMETER Path
        The folder to update.

    .PARAMETER DomainGroup
        The DOMAIN\group identity to grant. Mandatory - no default.

    .EXAMPLE
        Add-DeleteSubdirectoriesAndFilesACE -Path "E:\homedirs" -DomainGroup "sscclient161\perm-lipfs1-gmsa-special"
#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$DomainGroup
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
        $rights = [System.Security.AccessControl.FileSystemRights]::ReadExtendedAttributes -bor `
            [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor `
            [System.Security.AccessControl.FileSystemRights]::Synchronize

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

        Write-Host "ACE successfully added for '$DomainGroup' on '$Path'" -ForegroundColor Green
    } Catch {
        Write-Error "Failed to apply ACE: $_"
    }
}
