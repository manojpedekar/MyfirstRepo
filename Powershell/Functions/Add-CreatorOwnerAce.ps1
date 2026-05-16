Function Add-CreatorOwnerAce {
<#
    .SYNOPSIS
        Adds a CREATOR OWNER Modify+Synchronize ACE to a folder, propagated
        to children only.

    .DESCRIPTION
        Adds an InheritOnly access rule granting the CREATOR OWNER pseudo-
        identity Modify + Synchronize rights with ContainerInherit and
        ObjectInherit. This is the standard pattern for home-drive-style
        folders where each newly-created child item inherits ownership +
        Modify for the user that created it, without the parent folder
        itself being a target.

    .PARAMETER Path
        The folder to update. Must exist and be a directory.

    .EXAMPLE
        Add-CreatorOwnerAce -Path "E:\homedirs"

    .EXAMPLE
        Get-ChildItem D:\Shares -Directory | ForEach-Object {
            Add-CreatorOwnerAce -Path $_.FullName -Verbose
        }
#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    # Resolve the folder and its ACL
    If (-not (Test-Path -Path $Path -PathType Container)) {
        Throw "The path '$Path' does not exist or is not a folder."
    }
    $acl = Get-Acl -Path $Path

    # Build the access rule
    $identity = 'CREATOR OWNER'
    $rights = [System.Security.AccessControl.FileSystemRights]::Modify -bor `
        [System.Security.AccessControl.FileSystemRights]::Synchronize
    $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
        [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propFlags = [System.Security.AccessControl.PropagationFlags]::InheritOnly
    $ruleType = [System.Security.AccessControl.AccessControlType]::Allow

    $ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $identity, $rights, $inheritFlags, $propFlags, $ruleType
    )

    # Add it and persist
    $acl.AddAccessRule($ace)
    Set-Acl -Path $Path -AclObject $acl

    Write-Verbose "Added CREATOR OWNER Modify/Synchronize ACE to '$Path' (ContainerInherit, ObjectInherit; InheritOnly)."
}
