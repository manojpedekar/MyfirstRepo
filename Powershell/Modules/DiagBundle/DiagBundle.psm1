$ErrorActionPreference = 'Stop'

$script:DiagLogPath = $null

$privateRoot = Join-Path $PSScriptRoot 'Private'
$publicRoot  = Join-Path $PSScriptRoot 'Public'

$privateScripts = @(Get-ChildItem -Path $privateRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$publicScripts  = @(Get-ChildItem -Path $publicRoot  -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($script in @($privateScripts) + @($publicScripts)) {
    try {
        . $script.FullName
    }
    catch {
        Write-Error "Failed to load $($script.FullName): $_"
        throw
    }
}

Export-ModuleMember -Function $publicScripts.BaseName
