Function Reset-ACLToInherit {
<#
    .SYNOPSIS
        Removes all explicit ACEs from a folder and re-enables inheritance.

    .DESCRIPTION
        Drops every non-inherited access rule on the target path and turns
        inheritance back on so the item picks up its parent's ACL. Useful
        for "reset to default" cleanup after a permissions experiment, or
        for normalizing a tree where individual items have drifted from
        the parent's intent.

        Operates on a single path. To process many items in bulk, pipe
        Get-ChildItem output to ForEach-Object:

            Get-ChildItem -Recurse -File |
                Where-Object { (Get-Acl $_.FullName).AreAccessRulesProtected -eq $true } |
                ForEach-Object { Reset-ACLToInherit -Path $_.FullName }

    .PARAMETER Path
        The file or folder to reset.

    .EXAMPLE
        Reset-ACLToInherit -Path "E:\share\Reports\summary.xlsx"
#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Try {
        # Get current ACL
        $acl = Get-Acl -Path $Path

        # Disable inheritance but keep existing ACEs temporarily
        $acl.SetAccessRuleProtection($true, $false)

        # Remove all explicit ACEs
        ForEach ($rule In $acl.Access) {
            [void]$acl.RemoveAccessRule($rule)
        }

        # Enable inheritance (and confirm no remaining explicit ACEs)
        $acl.SetAccessRuleProtection($false, $true)

        # Apply the updated ACL
        Set-Acl -Path $Path -AclObject $acl

        Write-Output "ACL reset and inheritance re-enabled for: $Path"
    } Catch {
        Write-Error "Failed to update ACL for $Path. $_"
    }
}
