#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Build-DiagTimingsSummary' {

    It 'returns $null when the log file is absent' {
        InModuleScope DiagBundle {
            Build-DiagTimingsSummary -LogPath 'C:\definitely\does\not\exist\nope.log' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the log file has no timing entries' {
        InModuleScope DiagBundle {
            $entries = @(
                [ordered]@{ ts='2026-05-01T00:00:00.000Z'; severity='info'; collector='X'; message='starting' }
                [ordered]@{ ts='2026-05-01T00:00:01.000Z'; severity='info'; collector='X'; message='done' }
            )
            $tmp = Join-Path $env:TEMP ('timinglog_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
            $lines = $entries | ForEach-Object { $_ | ConvertTo-Json -Compress }
            [System.IO.File]::WriteAllText($tmp, ($lines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
            try {
                Build-DiagTimingsSummary -LogPath $tmp | Should -BeNullOrEmpty
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'aggregates per-collector seconds slowest first' {
        InModuleScope DiagBundle {
            $entries = @(
                [ordered]@{ ts='2026-05-01T00:00:00.000Z'; severity='info'; collector='A'; message='timing'; step='a1'; duration_ms=2000 }
                [ordered]@{ ts='2026-05-01T00:00:02.000Z'; severity='info'; collector='B'; message='timing'; step='b1'; duration_ms=10000 }
                [ordered]@{ ts='2026-05-01T00:00:12.000Z'; severity='info'; collector='A'; message='timing'; step='a2'; duration_ms=500 }
                [ordered]@{ ts='2026-05-01T00:00:13.000Z'; severity='info'; collector='C'; message='timing'; step='c1'; duration_ms=3000 }
            )
            $tmp = Join-Path $env:TEMP ('timinglog_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
            $lines = $entries | ForEach-Object { $_ | ConvertTo-Json -Compress }
            [System.IO.File]::WriteAllText($tmp, ($lines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
            try {
                $r = Build-DiagTimingsSummary -LogPath $tmp
                $r | Should -Not -BeNullOrEmpty
                @($r.by_collector_seconds.Keys)[0] | Should -Be 'B'
                @($r.by_collector_seconds.Keys)[1] | Should -Be 'C'
                @($r.by_collector_seconds.Keys)[2] | Should -Be 'A'
                $r.by_collector_seconds['B'] | Should -Be 10
                $r.by_collector_seconds['A'] | Should -Be 3
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'sorts steps[] by duration descending' {
        InModuleScope DiagBundle {
            $entries = @(
                [ordered]@{ ts='2026-05-01T00:00:00.000Z'; severity='info'; collector='A'; message='timing'; step='small'; duration_ms=10 }
                [ordered]@{ ts='2026-05-01T00:00:02.000Z'; severity='info'; collector='B'; message='timing'; step='huge';  duration_ms=99999 }
                [ordered]@{ ts='2026-05-01T00:00:12.000Z'; severity='info'; collector='C'; message='timing'; step='med';   duration_ms=500 }
            )
            $tmp = Join-Path $env:TEMP ('timinglog_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
            $lines = $entries | ForEach-Object { $_ | ConvertTo-Json -Compress }
            [System.IO.File]::WriteAllText($tmp, ($lines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
            try {
                $r = Build-DiagTimingsSummary -LogPath $tmp
                $r.steps[0].step | Should -Be 'huge'
                $r.steps[0].duration_ms | Should -Be 99999
                $r.steps[1].step | Should -Be 'med'
                $r.steps[2].step | Should -Be 'small'
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'tolerates malformed lines without aborting' {
        InModuleScope DiagBundle {
            $tmp = Join-Path $env:TEMP ('badlog_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
            $payload = @(
                'this is not json'
                ([ordered]@{ ts='2026-05-01T00:00:01.000Z'; severity='info'; collector='A'; message='timing'; step='good'; duration_ms=42 } | ConvertTo-Json -Compress)
                '{ "broken json'
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($tmp, $payload, [System.Text.UTF8Encoding]::new($false))
            try {
                $r = Build-DiagTimingsSummary -LogPath $tmp
                $r | Should -Not -BeNullOrEmpty
                $r.steps.Count | Should -Be 1
                $r.steps[0].step | Should -Be 'good'
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}
