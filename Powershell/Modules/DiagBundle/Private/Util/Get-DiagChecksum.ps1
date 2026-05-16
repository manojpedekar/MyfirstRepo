function Get-DiagChecksum {
    <#
    .SYNOPSIS
        Return the lowercase SHA256 hex digest of a file.

    .DESCRIPTION
        Thin wrapper around Get-FileHash that returns just the hash string in
        lowercase hex. Exists as a named function so unit tests can mock or
        substitute hashing without rewriting every call site, and so future
        algorithm changes (or pre-hashing optimisations) can be made in one
        place. Used by manifest builders and the bundle-level checksums pass.

    .PARAMETER Path
        Path to the file to hash. Mandatory. Must resolve to an existing file
        readable by the current user; otherwise Get-FileHash raises its
        standard error.

    .INPUTS
        None.

    .OUTPUTS
        [string]. Lowercase hexadecimal SHA256 digest, 64 characters, no
        prefix.

    .EXAMPLE
        # Hash the manifest before stamping it into checksums.txt.
        Get-DiagChecksum -Path 'C:\temp\bundle\manifest.json'

    .NOTES
        One-line wrapper that exists only for substitutability in tests. The
        algorithm is fixed at SHA256 to keep it consistent with the manifest
        artifact records and the top-level checksums.txt file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
