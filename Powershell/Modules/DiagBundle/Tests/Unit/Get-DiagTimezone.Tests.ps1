#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Get-DiagTimezone' {

    It 'returns all required keys' {
        InModuleScope DiagBundle {
            $tz = Get-DiagTimezone -WindowHours 24
            $tz.id                              | Should -Not -BeNullOrEmpty
            $tz.Contains('display_name')                     | Should -BeTrue
            $tz.Contains('current_utc_offset_minutes')       | Should -BeTrue
            $tz.Contains('currently_in_daylight_time')       | Should -BeTrue
            $tz.Contains('window_start_utc_offset_minutes')  | Should -BeTrue
            $tz.Contains('window_end_utc_offset_minutes')    | Should -BeTrue
            $tz.Contains('dst_transition_in_window')         | Should -BeTrue
            $tz.Contains('note')                             | Should -BeTrue
            $tz.note                                          | Should -Match 'local time'
        }
    }

    It 'reports a numeric current UTC offset that matches the local timezone' {
        InModuleScope DiagBundle {
            $tz = Get-DiagTimezone -WindowHours 24
            $expected = [int][System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::UtcNow).TotalMinutes
            $tz.current_utc_offset_minutes      | Should -Be $expected
            $tz.window_end_utc_offset_minutes   | Should -Be $expected
        }
    }
}

Describe 'ConvertFrom-DiagLocalTime' {

    It 'returns null for an input already in UTC' {
        InModuleScope DiagBundle {
            $utc = [DateTime]::UtcNow
            ConvertFrom-DiagLocalTime -LocalDateTime $utc | Should -BeNullOrEmpty
        }
    }

    It 'roundtrips a local time through to UTC' {
        InModuleScope DiagBundle {
            $localNow = [DateTime]::Now      # Kind = Local
            $utc      = ConvertFrom-DiagLocalTime -LocalDateTime $localNow
            $utc.Kind | Should -Be ([DateTimeKind]::Utc)
            # The roundtrip should land within a couple of seconds of UtcNow.
            ([Math]::Abs(($utc - [DateTime]::UtcNow).TotalSeconds)) | Should -BeLessThan 5
        }
    }
}
