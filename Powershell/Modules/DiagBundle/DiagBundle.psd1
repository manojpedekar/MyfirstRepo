@{
    RootModule           = 'DiagBundle.psm1'
    ModuleVersion        = '1.4.1'
    GUID                 = '2eb3da51-711d-47d4-b58e-3a736c7d2a6d'
    Author               = 'Pete Demers'
    CompanyName          = 'Unknown'
    Copyright            = '(c) Pete Demers. All rights reserved.'
    Description          = 'Collects a one-shot Windows Server diagnostic bundle (manifest.json + summary JSON + raw artifacts) for AI-assisted analysis.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Invoke-DiagBundle')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Diagnostics', 'Windows', 'Server', 'EventLog', 'Patching', 'Troubleshooting')
            ProjectUri   = ''
            LicenseUri   = ''
            ReleaseNotes = '1.4.1: Fix two PS 5.1 incompatibilities caught by first validation run: ProcessStartInfo.ArgumentList is .NET Core/5+ only, replaced with quoted .Arguments string in Get-DiagSalt._RunSaltCallProbe and Get-DiagInventory cloud-grains probe (Gaps 8, 10 now functional). Added cross-collector reconciliation in Invoke-DiagBundle: when boot_timeline (Kernel-General 12) disagrees with Win32_OperatingSystem.LastBootUpTime by >60s, the canonical kernel value overwrites manifest.host.last_boot_utc and summary/inventory.json, with last_boot_reconciled + last_boot_cim_value + last_boot_reconciliation_delta_seconds preserved for traceability. This fixes Gap 12 on virtualized hosts (notably OpenShift Virt) whose CIM stamps boot time before NTP correction. 1.4.0: Cloudbase-Init / Salt diagnostic deepening (post-2026-05-11 OpenShift Virt highstate investigation). New Get-DiagRoleCloudbaseInit captures log tails, conf files, LocalScripts contents + sha256, and parses the last run for plugin sequence, script outcomes, reboots; flags the "exit 0 + non-empty stderr" silent-failure pattern as a warning. Get-DiagSalt rewrite: tolerant YAML parser handles scalar/inline-list/block-list master forms (Gap 3); default-path log capture even when log_file unset (Gap 2); cached minion_id + minion.d drop-ins + static grains file capture (Gaps 6, 7); PKI inventory with master_sign.pub presence check raising error when verify_master_pubkey_sign:True (Gap 4); TCP probes to master 4505/4506 (Gap 5); live salt-call --local probes for test.ping/grains.items/saltutil.is_running plus state.show_top for active saltenv + base (Gap 8). New summary/salt_grains.json. New Resources/expected_tasks.json data-driven absence check (Gap 9); seed list contains SaltHighState only. inventory.json gains data.cloud block from grains (Gap 10) and a CIM_DATETIME parse for install_date/last_boot_utc that preserves the timezone offset correctly (Gap 12). Boot timeline labels cloudbase-init-initiated reboots correctly (Gap 11). EventLog message renderer falls back to joined EventData when the provider message resource is unregistered (Gap 13). 1.3.0: Per-step timing instrumentation. 1.2.0: Operator problem-description capture. 1.1.0: Boot timeline + structured time_zone + CrashControl/dump inventory + Salt collector.'
        }
    }
}
