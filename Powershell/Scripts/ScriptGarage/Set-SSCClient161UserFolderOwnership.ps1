<#
    .SYNOPSIS
        Walks user folders under the current directory, sets the folder owner
        to SSCCLIENT161\<username>, and adds a CREATOR OWNER Modify ACE that
        propagates to children only.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed 2025-06 against the
        SSCCLIENT161 fileserver user folders to repair ownership and child
        permissions during a perms remediation. Skips three specific
        operator accounts (KMahes, WBeaton, cnelson) that were intentionally
        left untouched.

        The Add-CreatorOwnerAce helper is preserved inline as the historical
        record of what was actually executed. The canonical version lives in
        Powershell/Functions/Add-CreatorOwnerAce.ps1.

        Do not re-run without confirming the target directory is correct
        (script uses cwd via `dir`) and that the SSCCLIENT161 prefix still
        applies.
#>

Function Add-CreatorOwnerAce {
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

    Write-Verbose "   Added CREATOR OWNER Modify/Synchronize ACE to '$Path' (ContainerInherit, ObjectInherit; InheritOnly)."
}

$UserFolders = dir | ? {$_.Name -notin @('KMahes','WBeaton', 'cnelson')}

ForEach ($userFolder In $UserFolders) {

    Try {
        # Force Get-ADUser to throw on not-found
        Remove-Variable ADUserExists -ErrorAction SilentlyContinue
        $ADUserExists = get-aduser $userfolder.name -ErrorAction SilentlyContinue | Out-Null

        Write-Host "Starting $($ADUserExists.samaccountname)" -ForegroundColor green
        icacls $userFolder.FullName /setowner "SSCCLIENT161\$($userFolder.BaseName)" /T /C /Q
        Add-CreatorOwnerAce -Path $userFolder.FullName -Verbose

    } Catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        # user not in AD
        Write-Warning "No User Found for $($userFolder.fullname)"
    }

}
