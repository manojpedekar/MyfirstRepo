function Compress-DiagBundle {
    <#
    .SYNOPSIS
        Compress a directory tree into a single ZIP file at optimal level.

    .DESCRIPTION
        Packages the staged bundle directory into the final ZIP delivered by
        Invoke-DiagBundle. Called as the last step of the pipeline, after
        manifest finalisation and checksum generation. Uses the
        System.IO.Compression.ZipFile .NET API rather than Compress-Archive so
        the function works on bundles larger than 2GB and runs faster on big
        trees. Overwrites any existing ZIP at the destination path.

    .PARAMETER Source
        Absolute path to the directory whose contents will be compressed.
        Mandatory. The directory itself is not included as the top-level entry
        (includeBaseDirectory is false).

    .PARAMETER Destination
        Absolute path where the ZIP will be written. Mandatory. If a file
        already exists at this path it is removed first.

    .INPUTS
        None.

    .OUTPUTS
        [long]. Size in bytes of the compressed ZIP file on disk.

    .EXAMPLE
        # Final pipeline step inside Invoke-DiagBundle.
        Compress-DiagBundle -Source $bundleRoot -Destination 'C:\ProgramData\DiagBundle\output\HOST_20260427-140000_diagbundle.zip'

    .NOTES
        Uses System.IO.Compression to dodge the PowerShell 5.1 Compress-Archive
        2GB limit and its slow path on large trees. CompressionLevel is fixed
        at Optimal because diagnostic artifacts (EVTX, text logs, JSON) compress
        well and the time difference versus Fastest is small at our typical
        bundle sizes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    $level = [System.IO.Compression.CompressionLevel]::Optimal
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $Source,
        $Destination,
        $level,
        $false
    )

    (Get-Item -LiteralPath $Destination).Length
}
