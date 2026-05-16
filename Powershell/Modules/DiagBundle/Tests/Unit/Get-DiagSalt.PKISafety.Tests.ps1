#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Safety-critical test: confirm Get-DiagSalt never names the PKI directory
# in any output path, in any branch. A passing test does not prove Salt is
# uninstalled-safe; it proves the source code does not enumerate the PKI
# tree. Pair with a manual review when changing copy paths in the collector.

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    $sourcePath = Join-Path $repoRoot 'DiagBundle\Private\Collectors\Get-DiagSalt.ps1'
    Import-Module $modulePath -Force
}

Describe 'Get-DiagSalt PKI safety' {

    It 'no executable line touches conf\pki, minion.pem, or pillar.items' {
        # Strip docstring/comment content before scanning, so documenting what
        # we deliberately do NOT collect does not trip the test.
        $raw = [System.IO.File]::ReadAllText($sourcePath)
        # Drop multi-line docstring blocks <# ... #>
        $code = [regex]::Replace($raw, '(?s)<\#.*?\#>', '')
        # Drop single-line comments
        $code = ($code -split "`n" | ForEach-Object {
            $line = $_
            # Strip everything from the first unquoted '#'. Crude but adequate
            # for this test: PowerShell allows '#' inside strings, so we
            # tolerate false negatives (something inside a string with a #
            # would not be considered code).
            if ($line -match '^\s*#') { '' } else { $line }
        }) -join "`n"

        $forbidden = @(
            'Copy-Item.*conf\\pki'
            'Get-ChildItem.*conf\\pki'
            'Get-Content.*conf\\pki'
            'ReadAllText.*conf\\pki'
            'ReadAllBytes.*conf\\pki'
            'minion\.pem'
            'pillar\.items'
        )
        foreach ($pattern in $forbidden) {
            $code | Should -Not -Match $pattern
        }
    }

    It 'declares the no-PKI / no-pillar safety stance in the .DESCRIPTION docstring' {
        $src = [System.IO.File]::ReadAllText($sourcePath)
        $src | Should -Match 'NEVER (?:reads or copies the PKI|executes pillar\.items|reads or copies)'
    }

    It 'returns Success and no PKI artifacts on a host with no Salt install' {
        InModuleScope DiagBundle {
            $tmp = Join-Path $env:TEMP ("DiagBundleSaltTest_" + [guid]::NewGuid())
            New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'raw\salt') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'summary')  | Out-Null
            try {
                $r = Get-DiagSalt -WorkingDirectory $tmp -WindowHours 24
                $r.Success | Should -BeTrue
                foreach ($a in $r.Artifacts) {
                    $a.path | Should -Not -Match 'pki'
                }
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
