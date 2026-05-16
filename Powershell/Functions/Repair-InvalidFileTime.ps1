
Function Repair-InvalidFileTime {
    <#
    .SYNOPSIS
        Repairs invalid LastWriteTime / LastWriteTimeUtc values on one or more files.

    .DESCRIPTION
        Some sync engines (e.g. Resilio Connect, OneDrive) reject files with timestamps
        before 1970-01-01. This function corrects those timestamps safely.
        If a file's LastWriteTime is earlier than 1970-01-01, it will be set to the
        file's CreationTime (or current time if CreationTime is also invalid).

    .PARAMETER Path
        One or more full file paths to repair. Wildcards are not expanded.

    .EXAMPLE
        Repair-InvalidFileTime -Path "D:\Data\Shared\File1.docx","D:\Docs\Old\File2.txt"

    .EXAMPLE
        Get-ChildItem D:\Data -Recurse -File | Select-Object -ExpandProperty FullName | Repair-InvalidFileTime

    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path
    )
    
    Begin {
        $threshold = [datetime]'1970-01-01'
    }
    
    Process {
        ForEach ($p In $Path) {
            Try {
                If (-not (Test-Path $p)) {
                    Write-Warning "File not found: $p"
                    Continue
                }
                
                $item = Get-Item -LiteralPath $p -ErrorAction Stop
                If ($item.PSIsContainer) {
                    Write-Verbose "Skipping folder: $p"
                    Continue
                }
                
                If ($item.LastWriteTime -lt $threshold) {
                    $newTime = If ($item.CreationTime -ge $threshold) {
                        $item.CreationTime
                    } Else {
                        Get-Date
                    }
                    
                    If ($PSCmdlet.ShouldProcess($item.FullName, "Set LastWriteTime to $newTime")) {
                        $item.LastWriteTime = $newTime
                        $item.LastWriteTimeUtc = $newTime.ToUniversalTime()
                        Write-Host "✔ Fixed: $($item.FullName)"
                    }
                } Else {
                    Write-Verbose "OK: $($item.FullName)"
                }
            } Catch {
                Write-Warning "Error processing $p : $($_.Exception.Message)"
            }
        }
    }
}
