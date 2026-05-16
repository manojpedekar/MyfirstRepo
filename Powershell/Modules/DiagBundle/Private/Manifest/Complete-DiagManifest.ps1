function Complete-DiagManifest {
    <#
    .SYNOPSIS
        Seal the manifest and write manifest.json into the bundle root.
    .DESCRIPTION
        Walk every declared artifact, fill in size_bytes and the SHA256 hash
        from the file on disk, and aggregate raw_uncompressed_bytes and
        summary_uncompressed_bytes by path prefix. Stamp completed_utc and
        duration_seconds on the collection block, then serialize the manifest
        as UTF-8 JSON without BOM. Invoke-DiagBundle calls this last, after
        redaction but before the ZIP step.
    .PARAMETER Manifest
        The manifest hashtable. Mutated in place: size fields populated,
        missing artifacts moved to collection_errors, completed_utc set.
    .PARAMETER BundleRoot
        Absolute path to the working directory holding the staged bundle
        contents. The artifact relative paths resolve against this root and
        manifest.json is written here.
    .PARAMETER CompletedUtc
        UTC time the collection finished. Stamped into completed_utc and
        used to compute duration_seconds against started_utc.
    .INPUTS
        None.
    .OUTPUTS
        System.String. Absolute path to the manifest.json file just written.
    .EXAMPLE
        $manifestPath = Complete-DiagManifest -Manifest $manifest `
            -BundleRoot $workDir -CompletedUtc ([DateTime]::UtcNow)
    .NOTES
        Any artifact declared by a collector but missing from disk at
        finalize time is dropped from the artifacts array and a warning is
        appended to collection_errors -- the bundle still ships, but the
        gap is recorded. zip_compressed_bytes stays at 0 because the
        manifest is sealed inside the bundle before the ZIP exists; the
        real compressed size is returned out-of-band by Invoke-DiagBundle.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Manifest,
        [Parameter(Mandatory)] [string] $BundleRoot,
        [Parameter(Mandatory)] [DateTime] $CompletedUtc
    )

    $rawBytes = 0L
    $summaryBytes = 0L
    $survivors = [System.Collections.ArrayList]::new()

    foreach ($a in $Manifest.artifacts) {
        $relPath = $a['path'] -replace '/', '\'
        $full    = Join-Path $BundleRoot $relPath

        if (-not (Test-Path -LiteralPath $full)) {
            [void]$Manifest.collection_errors.Add(@{
                artifact  = $a['path']
                collector = if ($a.Contains('collector')) { $a['collector'] } else { 'manifest' }
                reason    = 'declared artifact not found at finalize'
                severity  = 'warning'
            })
            continue
        }

        $info = Get-Item -LiteralPath $full -ErrorAction Stop
        $a['size_bytes'] = $info.Length
        $a['sha256']     = (Get-FileHash -Path $full -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($a['path'] -like 'raw/*')         { $rawBytes     += $info.Length }
        elseif ($a['path'] -like 'summary/*') { $summaryBytes += $info.Length }

        [void]$survivors.Add($a)
    }

    $Manifest.artifacts = $survivors
    $Manifest.size_budget.raw_uncompressed_bytes     = $rawBytes
    $Manifest.size_budget.summary_uncompressed_bytes = $summaryBytes

    $started = [DateTime]::Parse($Manifest.collection.started_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
    $Manifest.collection.completed_utc    = $CompletedUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $Manifest.collection.duration_seconds = [int]($CompletedUtc - $started).TotalSeconds

    $manifestPath = Join-Path $BundleRoot 'manifest.json'
    $json = $Manifest | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))

    $manifestPath
}
