#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Resolve-DiagProblemDescription' {

    Context 'no input' {
        It 'returns $null when nothing was supplied' {
            InModuleScope DiagBundle {
                $r = Resolve-DiagProblemDescription -UserInteractive $true
                $r | Should -BeNullOrEmpty
            }
        }
    }

    Context 'parameter conflict' {
        It 'throws when both ProblemDescription and ProblemDescriptionFile are supplied' {
            InModuleScope DiagBundle {
                {
                    Resolve-DiagProblemDescription -ProblemDescription 'x' -ProblemDescriptionFile 'C:\nope.txt' -UserInteractive $true
                } | Should -Throw -ExpectedMessage '*mutually exclusive*'
            }
        }
    }

    Context 'non-interactive guard for prompt' {
        It 'throws when -PromptForProblem is set in a non-interactive session' {
            InModuleScope DiagBundle {
                {
                    Resolve-DiagProblemDescription -PromptForProblem $true -UserInteractive $false
                } | Should -Throw -ExpectedMessage '*requires an interactive session*'
            }
        }
    }

    Context 'string input' {
        It 'records source = parameter and roundtrips text' {
            InModuleScope DiagBundle {
                $r = Resolve-DiagProblemDescription -ProblemDescription 'patched 04-26, server stuck' -UserInteractive $false
                $r.source             | Should -Be 'parameter'
                $r.text               | Should -Be 'patched 04-26, server stuck'
                $r.truncated_to_bytes | Should -BeNullOrEmpty
                $r.operator_name      | Should -Not -BeNullOrEmpty
                $r.supplied_at_utc    | Should -Match '^\d{4}-\d{2}-\d{2}T'
            }
        }

        It 'strips control characters except CR/LF/TAB' {
            InModuleScope DiagBundle {
                $dirty = "line1`r`nline2`twith tab`nbell:$([char]7) end"
                $r = Resolve-DiagProblemDescription -ProblemDescription $dirty -UserInteractive $false
                $r.text | Should -Not -Match ([regex]::Escape([string][char]7))
                $r.text | Should -Match 'line1\r\nline2\twith tab\nbell: end'
            }
        }

        It 'truncates input over 8 KB and records the original size' {
            InModuleScope DiagBundle {
                $big = 'a' * 9000
                $r = Resolve-DiagProblemDescription -ProblemDescription $big -UserInteractive $false
                $r.truncated_to_bytes | Should -Be 9000
                $r.text.Length        | Should -BeLessOrEqual 8192
                $r.text.Length        | Should -BeGreaterThan 8000
            }
        }
    }

    Context 'file input' {
        It 'reads the file and records source = file with original_path' {
            InModuleScope DiagBundle {
                $tmp = Join-Path $env:TEMP ('diagprobtest_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
                try {
                    [System.IO.File]::WriteAllText($tmp, 'incident INC0123 narrative', [System.Text.UTF8Encoding]::new($false))
                    $r = Resolve-DiagProblemDescription -ProblemDescriptionFile $tmp -UserInteractive $false
                    $r.source        | Should -Be 'file'
                    $r.text          | Should -Be 'incident INC0123 narrative'
                    $r.original_path | Should -Be $tmp
                }
                finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'throws when the file does not exist' {
            InModuleScope DiagBundle {
                {
                    Resolve-DiagProblemDescription -ProblemDescriptionFile 'C:\nope_definitely_missing.txt' -UserInteractive $false
                } | Should -Throw -ExpectedMessage '*not found*'
            }
        }
    }

    Context 'prompt with stub invoker' {
        It 'records source = prompt and uses the returned text' {
            InModuleScope DiagBundle {
                $stub = { param($Prefill) @{ status = 'ok'; text = 'typed via prompt'; prefill_seen = $Prefill } }
                $r = Resolve-DiagProblemDescription -PromptForProblem $true -UserInteractive $true -PromptInvoker $stub
                $r.source | Should -Be 'prompt'
                $r.text   | Should -Be 'typed via prompt'
            }
        }

        It 'records source = prompt_cancelled with empty text' {
            InModuleScope DiagBundle {
                $stub = { param($Prefill) @{ status = 'cancelled'; text = '' } }
                $r = Resolve-DiagProblemDescription -PromptForProblem $true -UserInteractive $true -PromptInvoker $stub
                $r.source | Should -Be 'prompt_cancelled'
                $r.text   | Should -Be ''
            }
        }

        It 'passes the string parameter through as the prefill' {
            InModuleScope DiagBundle {
                $script:seenPrefill = $null
                $stub = { param($Prefill) $script:seenPrefill = $Prefill; @{ status = 'ok'; text = $Prefill } }
                $null = Resolve-DiagProblemDescription -ProblemDescription 'first draft text' -PromptForProblem $true -UserInteractive $true -PromptInvoker $stub
                $script:seenPrefill | Should -Be 'first draft text'
            }
        }
    }
}
