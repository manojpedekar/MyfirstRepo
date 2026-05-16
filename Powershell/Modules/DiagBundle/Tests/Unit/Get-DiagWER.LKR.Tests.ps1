#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe '_BuildKernelDumpsInventory LiveKernelReports per-file behavior' {

    BeforeEach {
        $script:work = Join-Path $env:TEMP ('DiagBundleA25-' + [guid]::NewGuid().ToString('N'))
        foreach ($s in 'summary','raw','raw\dumps','transcript') {
            New-Item -ItemType Directory -Force -Path (Join-Path $script:work $s) | Out-Null
        }

        # Synthetic file fixtures: name, length, age in hours.
        $script:fixtures = @(
            @{ Name = 'lkr_in_window_small.dmp';   Length = 200MB;  AgeHours = 2  }   # in window, under 1GB cap
            @{ Name = 'lkr_in_window_large.dmp';   Length = 5GB;    AgeHours = 4  }   # in window, over 1GB cap
            @{ Name = 'lkr_out_of_window.dmp';     Length = 100MB;  AgeHours = 240 } # too old (> WindowDays=7 days)
        )
    }

    AfterEach {
        if (Test-Path $script:work) {
            Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'records every file in files[] with name, size, mtime, in_window, copied, skip_reason' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work; fixtures = $script:fixtures } {
            param($work, $fixtures)

            $lkrPath = Join-Path $env:windir 'LiveKernelReports'
            $now = Get-Date

            $synth = $fixtures | ForEach-Object {
                $f = $_
                [pscustomobject]@{
                    Name             = $f.Name
                    FullName         = (Join-Path $lkrPath $f.Name)
                    Length           = [long]$f.Length
                    LastWriteTime    = $now.AddHours(-1 * $f.AgeHours)
                    LastWriteTimeUtc = $now.AddHours(-1 * $f.AgeHours).ToUniversalTime()
                }
            }

            Mock Test-Path -ParameterFilter { $LiteralPath -eq $lkrPath } -MockWith { $true }
            Mock Get-ChildItem -ParameterFilter { $LiteralPath -eq $lkrPath } -MockWith { $synth }
            Mock Copy-Item -MockWith { } -Verifiable

            $cutoff = (Get-Date).AddDays(-7)
            $inv = _BuildKernelDumpsInventory `
                -Cutoff                $cutoff `
                -Fmt                   'yyyy-MM-ddTHH:mm:ss.fffZ' `
                -WorkingDirectory      $work `
                -IncludeCrashArtifacts $true `
                -LkrCopyCapBytes       1GB

            $lkr = $inv.KernelDumps.live_kernel_reports
            $lkr.files | Should -HaveCount 3
            $lkr.file_count | Should -Be 3

            $small = $lkr.files | Where-Object { $_.name -eq 'lkr_in_window_small.dmp' }
            $small.in_window   | Should -BeTrue
            $small.copied      | Should -BeTrue
            $small.skip_reason | Should -BeNullOrEmpty

            $large = $lkr.files | Where-Object { $_.name -eq 'lkr_in_window_large.dmp' }
            $large.in_window   | Should -BeTrue
            $large.copied      | Should -BeFalse
            $large.skip_reason | Should -Be 'over_per_file_cap'

            $old = $lkr.files | Where-Object { $_.name -eq 'lkr_out_of_window.dmp' }
            $old.in_window   | Should -BeFalse
            $old.copied      | Should -BeFalse
            $old.skip_reason | Should -Be 'out_of_window'

            $lkr.copied_count | Should -Be 1
            $lkr.copied_bytes | Should -Be 200MB
            $lkr.copy_cap_per_file_bytes | Should -Be 1GB

            @($inv.Artifacts | Where-Object { $_.category -eq 'live_kernel_report' }).Count | Should -Be 1
        }
    }

    It 'with IncludeCrashArtifacts=$false marks every file crash_artifacts_disabled and copies nothing' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work; fixtures = $script:fixtures } {
            param($work, $fixtures)

            $lkrPath = Join-Path $env:windir 'LiveKernelReports'
            $now = Get-Date

            $synth = $fixtures | ForEach-Object {
                $f = $_
                [pscustomobject]@{
                    Name             = $f.Name
                    FullName         = (Join-Path $lkrPath $f.Name)
                    Length           = [long]$f.Length
                    LastWriteTime    = $now.AddHours(-1 * $f.AgeHours)
                    LastWriteTimeUtc = $now.AddHours(-1 * $f.AgeHours).ToUniversalTime()
                }
            }

            Mock Test-Path -ParameterFilter { $LiteralPath -eq $lkrPath } -MockWith { $true }
            Mock Get-ChildItem -ParameterFilter { $LiteralPath -eq $lkrPath } -MockWith { $synth }
            Mock Copy-Item -MockWith { throw 'should never copy when disabled' }

            $cutoff = (Get-Date).AddDays(-7)
            $inv = _BuildKernelDumpsInventory `
                -Cutoff                $cutoff `
                -Fmt                   'yyyy-MM-ddTHH:mm:ss.fffZ' `
                -WorkingDirectory      $work `
                -IncludeCrashArtifacts $false `
                -LkrCopyCapBytes       1GB

            $lkr = $inv.KernelDumps.live_kernel_reports
            $lkr.files | Should -HaveCount 3
            ($lkr.files | Where-Object { $_.skip_reason -eq 'crash_artifacts_disabled' }).Count | Should -Be 3
            $lkr.copied_count | Should -Be 0
            $inv.Artifacts | Where-Object { $_.category -eq 'live_kernel_report' } | Should -BeNullOrEmpty
        }
    }

    It 'with LkrCopyCapBytes=0 marks every in-window file over_per_file_cap (index-only mode)' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work; fixtures = $script:fixtures } {
            param($work, $fixtures)

            $lkrPath = Join-Path $env:windir 'LiveKernelReports'
            $now = Get-Date

            $synth = $fixtures | ForEach-Object {
                $f = $_
                [pscustomobject]@{
                    Name             = $f.Name
                    FullName         = (Join-Path $lkrPath $f.Name)
                    Length           = [long]$f.Length
                    LastWriteTime    = $now.AddHours(-1 * $f.AgeHours)
                    LastWriteTimeUtc = $now.AddHours(-1 * $f.AgeHours).ToUniversalTime()
                }
            }

            Mock Test-Path -ParameterFilter { $LiteralPath -eq $lkrPath } -MockWith { $true }
            Mock Get-ChildItem -ParameterFilter { $LiteralPath -eq $lkrPath } -MockWith { $synth }
            Mock Copy-Item -MockWith { throw 'should never copy with cap=0' }

            $cutoff = (Get-Date).AddDays(-7)
            $inv = _BuildKernelDumpsInventory `
                -Cutoff                $cutoff `
                -Fmt                   'yyyy-MM-ddTHH:mm:ss.fffZ' `
                -WorkingDirectory      $work `
                -IncludeCrashArtifacts $true `
                -LkrCopyCapBytes       0

            $lkr = $inv.KernelDumps.live_kernel_reports
            $lkr.copy_cap_per_file_bytes | Should -Be 0
            $lkr.copied_count | Should -Be 0

            $inWindowEntries = $lkr.files | Where-Object { $_.in_window }
            $inWindowEntries.Count | Should -Be 2
            ($inWindowEntries | Where-Object { $_.skip_reason -eq 'over_per_file_cap' }).Count | Should -Be 2
        }
    }
}
