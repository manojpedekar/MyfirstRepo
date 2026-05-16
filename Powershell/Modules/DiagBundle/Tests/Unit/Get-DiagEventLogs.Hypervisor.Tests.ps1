#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Get-DiagEventLogs hypervisor-aware platform detection (A23)' {

    It 'detects VMware via Win32_ComputerSystem.Manufacturer' {
        InModuleScope DiagBundle {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'VMware, Inc.'; Model = 'VMware7,1' }
            }
            Mock Get-WinEvent -MockWith { @() }
            Mock Invoke-DiagTimed -MockWith { param($Action) & $Action }

            $work = Join-Path $env:TEMP ('DiagA23VMware-' + [guid]::NewGuid().ToString('N'))
            foreach ($s in 'summary','raw\eventlogs','transcript') { New-Item -ItemType Directory -Force -Path (Join-Path $work $s) | Out-Null }
            $script:DiagLogPath = Join-Path $work 'transcript\collector.log'
            Set-Content -Path $script:DiagLogPath -Value '' -Force
            try {
                $r = Get-DiagEventLogs -WorkingDirectory $work -WindowHours 1
                $r.Success | Should -BeTrue
                $sum = Get-Content (Join-Path $work 'summary\events_summary.json') -Raw | ConvertFrom-Json
                $sum.detected_platform | Should -Be 'vmware'
                $sum.schema_version    | Should -Be '1.1'
                ,$sum.interesting_providers | Should -BeOfType ([array])
            } finally {
                Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
            }
        }
    }

    It 'detects Hyper-V via Microsoft Corporation manufacturer' {
        InModuleScope DiagBundle {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine' }
            }
            Mock Get-WinEvent -MockWith { @() }
            Mock Invoke-DiagTimed -MockWith { param($Action) & $Action }

            $work = Join-Path $env:TEMP ('DiagA23HyperV-' + [guid]::NewGuid().ToString('N'))
            foreach ($s in 'summary','raw\eventlogs','transcript') { New-Item -ItemType Directory -Force -Path (Join-Path $work $s) | Out-Null }
            $script:DiagLogPath = Join-Path $work 'transcript\collector.log'
            Set-Content -Path $script:DiagLogPath -Value '' -Force
            try {
                $r = Get-DiagEventLogs -WorkingDirectory $work -WindowHours 1
                $sum = Get-Content (Join-Path $work 'summary\events_summary.json') -Raw | ConvertFrom-Json
                $sum.detected_platform | Should -Be 'hyperv'
            } finally {
                Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
            }
        }
    }

    It 'detects KVM via QEMU manufacturer' {
        InModuleScope DiagBundle {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'QEMU'; Model = 'Standard PC (Q35 + ICH9, 2009)' }
            }
            Mock Get-WinEvent -MockWith { @() }
            Mock Invoke-DiagTimed -MockWith { param($Action) & $Action }

            $work = Join-Path $env:TEMP ('DiagA23Kvm-' + [guid]::NewGuid().ToString('N'))
            foreach ($s in 'summary','raw\eventlogs','transcript') { New-Item -ItemType Directory -Force -Path (Join-Path $work $s) | Out-Null }
            $script:DiagLogPath = Join-Path $work 'transcript\collector.log'
            Set-Content -Path $script:DiagLogPath -Value '' -Force
            try {
                $r = Get-DiagEventLogs -WorkingDirectory $work -WindowHours 1
                $sum = Get-Content (Join-Path $work 'summary\events_summary.json') -Raw | ConvertFrom-Json
                $sum.detected_platform | Should -Be 'kvm'
            } finally {
                Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
            }
        }
    }

    It 'reports detected_platform=unknown on a physical / unrecognized manufacturer' {
        InModuleScope DiagBundle {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'PowerEdge R750' }
            }
            Mock Get-WinEvent -MockWith { @() }
            Mock Invoke-DiagTimed -MockWith { param($Action) & $Action }

            $work = Join-Path $env:TEMP ('DiagA23Phys-' + [guid]::NewGuid().ToString('N'))
            foreach ($s in 'summary','raw\eventlogs','transcript') { New-Item -ItemType Directory -Force -Path (Join-Path $work $s) | Out-Null }
            $script:DiagLogPath = Join-Path $work 'transcript\collector.log'
            Set-Content -Path $script:DiagLogPath -Value '' -Force
            try {
                $r = Get-DiagEventLogs -WorkingDirectory $work -WindowHours 1
                $sum = Get-Content (Join-Path $work 'summary\events_summary.json') -Raw | ConvertFrom-Json
                $sum.detected_platform | Should -Be 'unknown'
                # Base providers are always in scope; index field is present.
                ,$sum.interesting_providers | Should -BeOfType ([array])
            } finally {
                Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
            }
        }
    }
}
