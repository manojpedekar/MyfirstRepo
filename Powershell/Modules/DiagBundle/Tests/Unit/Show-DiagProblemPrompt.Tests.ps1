#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# These tests cover the structure and dispatch of the prompt subsystem
# without rendering the actual WinForms dialog (which requires an
# interactive desktop and would block a test run).

BeforeAll {
    $repoRoot       = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath     = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    $childPath      = Join-Path $repoRoot 'DiagBundle\Private\Util\Show-DiagProblemPrompt.Child.ps1'
    $parentPath     = Join-Path $repoRoot 'DiagBundle\Private\Util\Show-DiagProblemPrompt.ps1'
    Import-Module $modulePath -Force
}

Describe 'Form helper (_RenderDiagProblemForm in parent file)' {

    It 'sets TopMost = $true on the form' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        $src | Should -Match '\$form\.TopMost\s*=\s*\$true'
    }

    It 'AcceptButton/CancelButton are wired so Esc and Ctrl+Enter work' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        $src | Should -Match '\$form\.AcceptButton\s*=\s*\$okButton'
        $src | Should -Match '\$form\.CancelButton\s*=\s*\$cancelButton'
    }

    It 'returns status=cancelled when DialogResult is not OK' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        $src | Should -Match "status\s*=\s*'cancelled'"
        $src | Should -Match "status\s*=\s*'ok'"
    }
}

Describe 'Show-DiagProblemPrompt child script' {

    It 'is dot-source-safe (no top-level executable code unless args supplied)' {
        # Defensive check that the dispatch guard is in place. The module loader
        # dot-sources every .ps1 under Private at import time; a runaway form
        # call there would freeze every Import-Module DiagBundle.
        $src = [System.IO.File]::ReadAllText($childPath)
        $src | Should -Match '\$MyInvocation\.InvocationName\s*-ne\s*''\.\'''
        $src | Should -Match '\$args\.Count\s*-gt\s*0'
    }
}

Describe 'Show-DiagProblemPrompt parent dispatcher' {

    It 'spawns the child with -STA' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        $src | Should -Match "'-STA'"
    }

    It 'invokes the child via -File (not -Command)' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        $src | Should -Match "'-File'"
    }

    It 'cleans up its temp files in finally' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        # Both the input prefill file and the output result file should be removed.
        $src | Should -Match 'Remove-Item.*\$inFile'
        $src | Should -Match 'Remove-Item.*\$outFile'
    }
}

Describe 'Module loads cleanly with the child script present' {
    It 'imports DiagBundle without invoking the form' {
        # If the child were to fall through and try to render a form during
        # dot-source, this Import-Module would hang or throw on a non-STA
        # build agent. Re-importing is a smoke test for the dispatch guard.
        { Import-Module $modulePath -Force } | Should -Not -Throw
        (Get-Module DiagBundle).Version.ToString() | Should -Be '1.3.0'
    }
}

Describe 'Show-DiagProblemPrompt apartment-state branching' {

    It 'parent dispatcher branches on STA before reaching Start-Process' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        # The STA branch must short-circuit and call _RenderDiagProblemForm
        # in-process, returning before any Start-Process call. The test is
        # forgiving of the exact phrasing (variable hoist or inline check)
        # but requires the GetApartmentState string and the in-process return.
        $src | Should -Match 'GetApartmentState\(\)'
        $src | Should -Match "-eq\s+'STA'"
        $src | Should -Match 'return\s+_RenderDiagProblemForm'
    }

    It '_RenderDiagProblemForm is defined in the parent file (shared helper)' {
        $src = [System.IO.File]::ReadAllText($parentPath)
        $src | Should -Match 'function\s+_RenderDiagProblemForm'
        # Form-specific code lives in the helper, not duplicated in the dispatcher
        $src | Should -Match 'New-Object\s+System\.Windows\.Forms\.Form'
    }

    It 'child script delegates to the shared helper rather than rebuilding the form' {
        $src = [System.IO.File]::ReadAllText($childPath)
        $src | Should -Match '_RenderDiagProblemForm'
        # The child no longer constructs the form itself; that code moved
        # to the shared helper.
        $src | Should -Not -Match 'System\.Windows\.Forms\.Form'
    }
}
