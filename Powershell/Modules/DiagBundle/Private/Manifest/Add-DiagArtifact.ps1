function Add-DiagArtifact {
    <#
    .SYNOPSIS
        Append one artifact entry to the manifest artifacts array.
    .DESCRIPTION
        Validate the required keys and push the entry onto
        manifest.artifacts. Each collector calls this for every file it
        produces. The entry is a free-form hashtable so collectors can attach
        type-specific metadata (channel name, row count, source artifacts)
        alongside the required fields. No file IO happens here.
    .PARAMETER Manifest
        The manifest hashtable produced by Initialize-DiagManifest. Mutated
        in place.
    .PARAMETER Artifact
        Hashtable describing one artifact. Must contain path (forward-slash
        relative path inside the bundle), category (short tag like
        events_summary or eventlog_raw), and type (derived or raw). Any other
        keys pass through unchanged.
    .INPUTS
        None.
    .OUTPUTS
        None. Mutates the manifest hashtable in place.
    .EXAMPLE
        Add-DiagArtifact -Manifest $manifest -Artifact @{
            path = 'summary/inventory.json'; category = 'inventory'; type = 'derived'
        }
    .NOTES
        Throws if path, category, or type is missing -- this is a fast fail
        for collector bugs, not a runtime condition. size_bytes and sha256
        are intentionally not set here; Complete-DiagManifest fills them in
        lazily once every file is on disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Manifest,
        [Parameter(Mandatory)] [hashtable] $Artifact
    )

    if (-not $Artifact.Contains('path'))     { throw 'Artifact requires path.' }
    if (-not $Artifact.Contains('category')) { throw 'Artifact requires category.' }
    if (-not $Artifact.Contains('type'))     { throw 'Artifact requires type (derived|raw).' }

    [void]$Manifest.artifacts.Add($Artifact)
}
