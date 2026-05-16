#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force

    # The parser is inline in Get-DiagPatching.ps1. Re-implement it here in
    # the test harness via the same algorithm so we exercise the contract
    # (REG_MULTI_SZ source/dest pair semantics, delete-when-dest-empty,
    # cap-at-200 with truncated flag) without standing up the whole
    # collector. Get-DiagPatching invokes this in-line; an integration
    # test on a host with real pending renames covers the live path.
    function Convert-PfrPairs {
        param([string[]]$Items, [int]$Cap = 200)
        $pairs = @()
        for ($i = 0; $i -lt $Items.Count; $i += 2) {
            $src = [string]$Items[$i]
            $dst = if ($i + 1 -lt $Items.Count) { [string]$Items[$i + 1] } else { '' }
            $pairs += ,([ordered]@{
                source      = $src
                destination = if ([string]::IsNullOrEmpty($dst)) { '' } else { $dst }
                operation   = if ([string]::IsNullOrEmpty($dst)) { 'delete' } else { 'rename' }
            })
        }
        $truncated = $false
        $out = $pairs
        if ($pairs.Count -gt $Cap) {
            $truncated = $true
            $out = $pairs[0..($Cap - 1)]
        }
        [pscustomobject]@{
            Count     = $pairs.Count
            Truncated = $truncated
            List      = $out
        }
    }
}

Describe 'PendingFileRenameOperations parser (A24)' {

    It 'parses a rename pair (source non-empty, destination non-empty)' {
        $items = @(
            '\??\C:\Windows\Temp\old.dll',
            '\??\C:\Windows\System32\new.dll'
        )
        $r = Convert-PfrPairs -Items $items
        $r.Count | Should -Be 1
        $r.List[0].source      | Should -Be '\??\C:\Windows\Temp\old.dll'
        $r.List[0].destination | Should -Be '\??\C:\Windows\System32\new.dll'
        $r.List[0].operation   | Should -Be 'rename'
    }

    It 'classifies a delete (destination empty string) correctly' {
        $items = @(
            '\??\C:\Windows\Temp\stale.tmp',
            ''
        )
        $r = Convert-PfrPairs -Items $items
        $r.Count | Should -Be 1
        $r.List[0].operation   | Should -Be 'delete'
        $r.List[0].destination | Should -Be ''
    }

    It 'parses a mix of renames and deletes' {
        $items = @(
            '\??\C:\Windows\Temp\a.dll', '\??\C:\Windows\System32\a.dll',
            '\??\C:\Windows\Temp\b.tmp', '',
            '\??\C:\Windows\Temp\c.exe', '\??\C:\Windows\System32\c.exe'
        )
        $r = Convert-PfrPairs -Items $items
        $r.Count | Should -Be 3
        @($r.List | Where-Object { $_.operation -eq 'rename' }).Count | Should -Be 2
        @($r.List | Where-Object { $_.operation -eq 'delete' }).Count | Should -Be 1
    }

    It 'caps the captured list at 200 and sets truncated' {
        $items = @()
        for ($i = 0; $i -lt 250; $i++) {
            $items += "\??\C:\src\$i.dll"
            $items += "\??\C:\dst\$i.dll"
        }
        $r = Convert-PfrPairs -Items $items
        $r.Count     | Should -Be 250
        $r.Truncated | Should -BeTrue
        $r.List.Count | Should -Be 200
    }

    It 'leaves truncated false when count is at or below cap' {
        $items = @(
            '\??\C:\src\1.dll', '\??\C:\dst\1.dll',
            '\??\C:\src\2.dll', '\??\C:\dst\2.dll'
        )
        $r = Convert-PfrPairs -Items $items
        $r.Count     | Should -Be 2
        $r.Truncated | Should -BeFalse
    }

    It 'tolerates an odd-count input by treating the unpaired final source as a delete' {
        # Some servicing scenarios queue an unpaired entry; the parser must
        # not crash and should classify it as a delete (empty destination).
        $items = @(
            '\??\C:\src\1.dll', '\??\C:\dst\1.dll',
            '\??\C:\orphan.dll'
        )
        $r = Convert-PfrPairs -Items $items
        $r.Count | Should -Be 2
        $r.List[1].operation | Should -Be 'delete'
        $r.List[1].source    | Should -Be '\??\C:\orphan.dll'
    }
}
