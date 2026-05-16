#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $modulePath = Join-Path $repoRoot 'DiagBundle\DiagBundle.psd1'
    Import-Module $modulePath -Force
}

Describe 'Get-DiagRoleHypervisor detection table (A22)' {

    BeforeEach {
        $script:work = Join-Path $env:TEMP ('DiagA22-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:work | Out-Null
    }

    AfterEach {
        if (Test-Path $script:work) {
            Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'dispatches to Get-DiagHvVMware on VMware manufacturer' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work } {
            param($work)
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'VMware, Inc.'; Model = 'VMware7,1' }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } -MockWith {
                [pscustomobject]@{ SMBIOSBIOSVersion = '6.00'; SerialNumber = 'VMware-XX' }
            }
            Mock Get-DiagHvVMware -Verifiable -MockWith { $HvData.Value.guest_agent_name = 'VMware Tools (test)' }
            Mock Get-DiagHvHyperV -MockWith { throw 'should not run' }
            Mock Get-DiagHvKvm    -MockWith { throw 'should not run' }

            $r = Get-DiagRoleHypervisor -WorkingDirectory $work
            $r.Success | Should -BeTrue
            Assert-MockCalled Get-DiagHvVMware -Times 1 -Exactly

            $sum = Get-Content (Join-Path $work 'summary\hypervisor.json') -Raw | ConvertFrom-Json
            $sum.data.detected_platform | Should -Be 'vmware'
            $sum.data.is_virtualized    | Should -BeTrue
            $sum.data.guest_agent_name  | Should -Be 'VMware Tools (test)'
        }
    }

    It 'dispatches to Get-DiagHvHyperV on Microsoft Corporation + Virtual Machine model' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work } {
            param($work)
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine' }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } -MockWith {
                [pscustomobject]@{ SMBIOSBIOSVersion = 'Hyper-V UEFI Release v4.0'; SerialNumber = '0001-1234' }
            }
            Mock Get-DiagHvVMware -MockWith { throw 'should not run' }
            Mock Get-DiagHvHyperV -Verifiable -MockWith { }
            Mock Get-DiagHvKvm    -MockWith { throw 'should not run' }

            $r = Get-DiagRoleHypervisor -WorkingDirectory $work
            Assert-MockCalled Get-DiagHvHyperV -Times 1 -Exactly
            $sum = Get-Content (Join-Path $work 'summary\hypervisor.json') -Raw | ConvertFrom-Json
            $sum.data.detected_platform | Should -Be 'hyperv'
        }
    }

    It 'dispatches to Get-DiagHvKvm on QEMU manufacturer' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work } {
            param($work)
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'QEMU'; Model = 'Standard PC (Q35 + ICH9, 2009)' }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } -MockWith {
                [pscustomobject]@{ SMBIOSBIOSVersion = 'rel-1.16'; SerialNumber = '' }
            }
            Mock Get-DiagHvVMware -MockWith { throw 'should not run' }
            Mock Get-DiagHvHyperV -MockWith { throw 'should not run' }
            Mock Get-DiagHvKvm    -Verifiable -MockWith { }

            $r = Get-DiagRoleHypervisor -WorkingDirectory $work
            Assert-MockCalled Get-DiagHvKvm -Times 1 -Exactly
            $sum = Get-Content (Join-Path $work 'summary\hypervisor.json') -Raw | ConvertFrom-Json
            $sum.data.detected_platform | Should -Be 'kvm'
        }
    }

    It 'dispatches to Get-DiagHvKvm on Red Hat manufacturer' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work } {
            param($work)
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'Red Hat'; Model = 'KVM' }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } -MockWith {
                [pscustomobject]@{ SMBIOSBIOSVersion = '1.0'; SerialNumber = '' }
            }
            Mock Get-DiagHvKvm -Verifiable -MockWith { }

            $r = Get-DiagRoleHypervisor -WorkingDirectory $work
            Assert-MockCalled Get-DiagHvKvm -Times 1 -Exactly
            $sum = Get-Content (Join-Path $work 'summary\hypervisor.json') -Raw | ConvertFrom-Json
            $sum.data.detected_platform | Should -Be 'kvm'
        }
    }

    It 'reports detected_platform=physical and is_virtualized=$false on a recognized physical model' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work } {
            param($work)
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'PowerEdge R750' }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } -MockWith {
                [pscustomobject]@{ SMBIOSBIOSVersion = '2.10.4'; SerialNumber = 'ABCDEF' }
            }
            Mock Get-DiagHvVMware -MockWith { throw 'should not run' }
            Mock Get-DiagHvHyperV -MockWith { throw 'should not run' }
            Mock Get-DiagHvKvm    -MockWith { throw 'should not run' }

            $r = Get-DiagRoleHypervisor -WorkingDirectory $work
            $r.Success | Should -BeTrue
            $sum = Get-Content (Join-Path $work 'summary\hypervisor.json') -Raw | ConvertFrom-Json
            $sum.data.detected_platform | Should -Be 'physical'
            $sum.data.is_virtualized    | Should -BeFalse
        }
    }

    It 'reports detected_platform=unknown on an unrecognized manufacturer/model' {
        InModuleScope DiagBundle -Parameters @{ work = $script:work } {
            param($work)
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } -MockWith {
                [pscustomobject]@{ Manufacturer = 'Some Unknown Hypervisor'; Model = 'GenericVM-1' }
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } -MockWith {
                [pscustomobject]@{ SMBIOSBIOSVersion = '?'; SerialNumber = '' }
            }
            Mock Get-DiagHvVMware -MockWith { throw 'should not run' }
            Mock Get-DiagHvHyperV -MockWith { throw 'should not run' }
            Mock Get-DiagHvKvm    -MockWith { throw 'should not run' }

            $r = Get-DiagRoleHypervisor -WorkingDirectory $work
            $r.Success | Should -BeTrue
            $sum = Get-Content (Join-Path $work 'summary\hypervisor.json') -Raw | ConvertFrom-Json
            $sum.data.detected_platform | Should -Be 'unknown'
            # is_virtualized stays $true so the agent does not assume physical.
            $sum.data.is_virtualized    | Should -BeTrue
        }
    }
}
