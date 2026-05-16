#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Build-DiagBootTimeline' {

    Context 'empty input' {
        It 'returns empty boots/gaps/anomalies for no events' {
            InModuleScope DiagBundle {
                $r = Build-DiagBootTimeline -SystemEvents @() -FromUtc ([DateTime]'2026-01-01Z') -ToUtc ([DateTime]'2026-01-02Z')
                $r.boots.Count     | Should -Be 0
                $r.gaps.Count      | Should -Be 0
                $r.anomalies.Count | Should -Be 0
                $r.summary.total_boots_in_window | Should -Be 0
            }
        }
    }

    Context 'single clean boot, no shutdown event (still running)' {
        It 'classifies the boot as ongoing with positive uptime' {
            InModuleScope DiagBundle {
                $startUtc = [DateTime]'2026-04-30T10:00:00Z'
                $events = @(
                    [pscustomobject]@{ Id = 12;   ProviderName = 'Microsoft-Windows-Kernel-General'; TimeCreated = $startUtc;             Message = '' }
                    [pscustomobject]@{ Id = 6005; ProviderName = 'EventLog';                          TimeCreated = $startUtc.AddSeconds(7); Message = '' }
                    [pscustomobject]@{ Id = 6013; ProviderName = 'EventLog';                          TimeCreated = $startUtc.AddSeconds(8); Message = 'uptime' }
                )
                $r = Build-DiagBootTimeline -SystemEvents $events -FromUtc $startUtc.AddHours(-1) -ToUtc $startUtc.AddHours(2)
                $r.boots.Count             | Should -Be 1
                $r.boots[0].boot_type      | Should -Be 'clean'
                $r.boots[0].shutdown_type  | Should -Be 'ongoing'
                $r.boots[0].shutdown_utc   | Should -BeNullOrEmpty
                $r.boots[0].uptime_seconds | Should -BeGreaterThan 0
                $r.anomalies.Count         | Should -Be 0
            }
        }
    }

    Context 'dirty boot from a 6008 with prior-shutdown timestamp inside window' {
        It 'flags incomplete_boot when the inferred prior shutdown is more than 30 minutes before the recovery boot' {
            InModuleScope DiagBundle {
                # The 6008 message text uses the host's local timezone. Build a message
                # whose embedded local time corresponds to 90 minutes before a chosen
                # recovery UTC, so the parser converts it back to the right UTC.
                $recoveryUtc = [DateTime]::UtcNow.Date.AddHours(14)
                $priorLocal  = [System.TimeZoneInfo]::ConvertTimeFromUtc($recoveryUtc.AddMinutes(-90), [System.TimeZoneInfo]::Local)
                $priorMsg    = "The previous system shutdown at $($priorLocal.ToString('h:mm:ss tt', [Globalization.CultureInfo]::InvariantCulture)) on $($priorLocal.ToString('M/d/yyyy', [Globalization.CultureInfo]::InvariantCulture)) was unexpected."

                $events = @(
                    [pscustomobject]@{ Id = 12;   ProviderName = 'Microsoft-Windows-Kernel-General'; TimeCreated = $recoveryUtc;             Message = '' }
                    [pscustomobject]@{ Id = 41;   ProviderName = 'Microsoft-Windows-Kernel-Power';   TimeCreated = $recoveryUtc.AddSeconds(2); Message = '' }
                    [pscustomobject]@{ Id = 6005; ProviderName = 'EventLog';                          TimeCreated = $recoveryUtc.AddSeconds(7); Message = '' }
                    [pscustomobject]@{ Id = 6008; ProviderName = 'EventLog';                          TimeCreated = $recoveryUtc.AddSeconds(7); Message = $priorMsg }
                )
                $r = Build-DiagBootTimeline -SystemEvents $events -FromUtc $recoveryUtc.AddHours(-24) -ToUtc $recoveryUtc.AddHours(2)
                $r.boots[0].boot_type          | Should -Be 'dirty'
                $r.boots[0].boot_type_evidence | Should -Match 'Kernel-Power 41'
                $r.boots[0].boot_type_evidence | Should -Match '6008'

                $incomplete = @($r.anomalies | Where-Object { $_.type -eq 'incomplete_boot' })
                $incomplete.Count | Should -BeGreaterThan 0
                $incomplete[0].severity | Should -BeIn @('warning', 'critical')
            }
        }
    }

    Context 'two boots with abnormal gap > 12 hours' {
        It 'emits abnormal_gap anomaly with critical severity' {
            InModuleScope DiagBundle {
                $boot1Start = [DateTime]'2026-04-25T10:00:00Z'
                $boot1End   = [DateTime]'2026-04-25T12:00:00Z'
                $boot2Start = [DateTime]'2026-04-26T01:00:00Z'   # 13h gap -> critical

                $events = @(
                    [pscustomobject]@{ Id = 12;   ProviderName = 'Microsoft-Windows-Kernel-General'; TimeCreated = $boot1Start;              Message = '' }
                    [pscustomobject]@{ Id = 6005; ProviderName = 'EventLog';                          TimeCreated = $boot1Start.AddSeconds(5); Message = '' }
                    [pscustomobject]@{ Id = 1074; ProviderName = 'User32';                            TimeCreated = $boot1End;                 Message = 'The process C:\Windows\Explorer.EXE (HOST) has initiated the restart of computer HOST on behalf of user HOST\Administrator for the following reason: Other (Unplanned)' }
                    [pscustomobject]@{ Id = 6006; ProviderName = 'EventLog';                          TimeCreated = $boot1End.AddSeconds(1);   Message = '' }
                    [pscustomobject]@{ Id = 109;  ProviderName = 'Microsoft-Windows-Kernel-Power';    TimeCreated = $boot1End.AddSeconds(2);   Message = '' }

                    [pscustomobject]@{ Id = 12;   ProviderName = 'Microsoft-Windows-Kernel-General'; TimeCreated = $boot2Start;              Message = '' }
                    [pscustomobject]@{ Id = 6005; ProviderName = 'EventLog';                          TimeCreated = $boot2Start.AddSeconds(5); Message = '' }
                )
                $r = Build-DiagBootTimeline -SystemEvents $events -FromUtc $boot1Start.AddHours(-1) -ToUtc $boot2Start.AddHours(1)
                $r.boots.Count | Should -Be 2

                $abnormal = @($r.anomalies | Where-Object { $_.type -eq 'abnormal_gap' })
                $abnormal.Count | Should -BeGreaterThan 0
                $abnormal[0].severity | Should -Be 'critical'
            }
        }
    }

    Context 'shutdown_initiator classification respects RID 500 rename' {
        It 'parses User32 1074 message into process/user/reason' {
            InModuleScope DiagBundle {
                $msg = 'The process C:\Windows\Explorer.EXE (HOST) has initiated the restart of computer HOST on behalf of user HOST\Administrator for the following reason: Other (Unplanned)'
                $parsed = _ParseUser32_1074 $msg
                $parsed.User    | Should -Be 'HOST\Administrator'
                $parsed.Process | Should -Match 'Explorer.EXE'
                $parsed.Reason  | Should -Match 'Other'
            }
        }

        It 'recognizes the leading-underscore renamed-Administrator pattern in the fallback path' {
            InModuleScope DiagBundle {
                _IsBuiltInAdminAccount -AccountName 'HOST\_lslocal' | Should -BeTrue
                _IsBuiltInAdminAccount -AccountName 'HOST\jdoe'     | Should -BeFalse
            }
        }

        It 'maps Explorer process to interactive_admin_console for an admin' {
            InModuleScope DiagBundle {
                _ClassifyInitiator -Process 'C:\Windows\Explorer.EXE' -IsAdminRid500 $true  | Should -Be 'interactive_admin_console'
                _ClassifyInitiator -Process 'C:\Windows\Explorer.EXE' -IsAdminRid500 $false | Should -Be 'interactive_user_console'
            }
        }

        It 'maps python.exe to salt_orchestrator regardless of admin status' {
            InModuleScope DiagBundle {
                _ClassifyInitiator -Process 'C:\Program Files\Salt Project\Salt\python.exe' -IsAdminRid500 $true  | Should -Be 'salt_orchestrator'
                _ClassifyInitiator -Process 'python.exe'                                     -IsAdminRid500 $false | Should -Be 'salt_orchestrator'
            }
        }
    }

    Context 'duration formatting' {
        It 'formats short and long durations sensibly' {
            InModuleScope DiagBundle {
                _HumanDuration 0     | Should -Be '0s'
                _HumanDuration 45    | Should -Be '45s'
                _HumanDuration 90    | Should -Be '1m 30s'
                _HumanDuration 3661  | Should -Be '1h 1m 1s'
                _HumanDuration 90000 | Should -Be '1d 1h'
            }
        }
    }
}
