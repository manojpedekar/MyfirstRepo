#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Invoke-DiagTimed' {

    It 'returns the scriptblock value verbatim' {
        InModuleScope DiagBundle {
            $r = Invoke-DiagTimed -Collector 'TEST' -Step 'returns-value' -Action { 42 }
            $r | Should -Be 42
        }
    }

    It 'preserves array output via the pipeline' {
        InModuleScope DiagBundle {
            $r = Invoke-DiagTimed -Collector 'TEST' -Step 'returns-array' -Action { 1, 2, 3 }
            ,$r | Should -BeOfType ([array])
            $r.Count | Should -Be 3
            $r[0] | Should -Be 1
        }
    }

    It 'captures $LASTEXITCODE from an external command' {
        InModuleScope DiagBundle {
            $tmpLog = Join-Path $env:TEMP ('diagtimed_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
            Set-Content -Path $tmpLog -Value '' -Encoding UTF8 -Force
            $script:DiagLogPath = $tmpLog
            try {
                Invoke-DiagTimed -Collector 'TEST' -Step 'cmd-exit-7' -Action { & cmd /c 'exit 7' 2>&1 } | Out-Null
                $line = Get-Content $tmpLog | Where-Object { $_ -match '"step":"cmd-exit-7"' } | Select-Object -First 1
                $line | Should -Not -BeNullOrEmpty
                $entry = $line | ConvertFrom-Json
                $entry.exit_code | Should -Be 7
                $entry.duration_ms | Should -BeGreaterOrEqual 0
            } finally {
                Remove-Item -LiteralPath $tmpLog -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'writes a timing log entry with collector + step + duration_ms even when the action throws' {
        InModuleScope DiagBundle {
            $tmpLog = Join-Path $env:TEMP ('diagtimed_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.log')
            Set-Content -Path $tmpLog -Value '' -Encoding UTF8 -Force
            $script:DiagLogPath = $tmpLog
            try {
                { Invoke-DiagTimed -Collector 'TEST' -Step 'will-throw' -Action { throw 'boom' } } | Should -Throw -ExpectedMessage '*boom*'
                $line = Get-Content $tmpLog | Where-Object { $_ -match '"step":"will-throw"' } | Select-Object -First 1
                $line | Should -Not -BeNullOrEmpty
                $entry = $line | ConvertFrom-Json
                $entry.collector | Should -Be 'TEST'
                $entry.message   | Should -Be 'timing'
            } finally {
                Remove-Item -LiteralPath $tmpLog -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
