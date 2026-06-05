# ============================================================
# Windows Server Edition Upgrade: Standard → Datacenter
# ============================================================

{%- set kms_keys = {
  '2012':   '48HP8-DN98B-MYWDG-T2DCC-8W83P',
  '2012R2': 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9',
  '2016':   'CB7KF-BWN84-R7R2Y-793K2-8XDDG',
  '2019':   'WMDGN-G9PQG-XVVXX-R3X43-63DFG',
  '2022':   'WX4NM-KYWYW-QJJR4-XV3QB-6VM33',
  '2025':   'D764K-2NDRG-47T6Q-P8T8W-YP6DF'
} -%}

# ------------------------------------------------------------
# 1. Detect OS Edition and Version
# ------------------------------------------------------------
check_os_info:
  cmd.run:
    - shell: powershell
    - name: |
        $os = Get-CimInstance Win32_OperatingSystem
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        Write-Output "Edition=$edition"
        Write-Output "Caption=$($os.Caption)"
    - stateful: False


# ------------------------------------------------------------
# 2. Perform Edition Upgrade (only if not Datacenter)
# ------------------------------------------------------------
os_edition_upgrade:
  cmd.run:
    - shell: powershell
    - name: |
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $caption  = (Get-CimInstance Win32_OperatingSystem).Caption

        if ($edition -eq 'ServerDatacenter') {
            Write-Output "Already Datacenter edition. No action required."
            exit 0
        }

        # KMS keys injected by Jinja at render time — single source of truth
        $kmsKeys = @{
{%- for version, key in kms_keys.items() %}
            '{{ version }}' = '{{ key }}'
{%- endfor %}
        }

        $key = $null
        switch -Regex ($caption) {
            '2012 R2' { $key = $kmsKeys['2012R2'] }
            '2012'    { $key = $kmsKeys['2012'] }
            '2016'    { $key = $kmsKeys['2016'] }
            '2019'    { $key = $kmsKeys['2019'] }
            '2022'    { $key = $kmsKeys['2022'] }
            '2025'    { $key = $kmsKeys['2025'] }
            default {
                Write-Error "Unsupported OS version: $caption"
                exit 1
            }
        }

        if (-not $key) {
            Write-Error "No KMS key resolved for OS: $caption"
            exit 1
        }

        Write-Output "Upgrading $edition to ServerDatacenter using DISM..."

        dism /online /Set-Edition:ServerDatacenter `
             /ProductKey:$key `
             /AcceptEula `
             /Quiet `
             /NoRestart

        exit $LASTEXITCODE

    - onlyif:
        - fun: cmd.run
          name: |
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -ne 'ServerDatacenter') { exit 0 } else { exit 1 }
          shell: powershell

    - onfail:
      - cmd: os_edition_upgrade_failed

    - require_in:
      - cmd: os_edition_activation


# ------------------------------------------------------------
# 3. Activate Windows after upgrade
# ------------------------------------------------------------
os_edition_activation:
  cmd.run:
    - shell: powershell
    - name: |
        Write-Output "Activating Windows via KMS..."
        cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato

    - onlyif:
        - fun: cmd.run
          name: |
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -eq 'ServerDatacenter') { exit 0 } else { exit 1 }
          shell: powershell

    - require:
      - cmd: os_edition_upgrade


# ------------------------------------------------------------
# 4. Failure Handler
# ------------------------------------------------------------
os_edition_upgrade_failed:
  cmd.run:
    - shell: powershell
    - name: Write-Error "OS Edition upgrade failed. Check DISM logs."
    - failhard: True


# ------------------------------------------------------------
# 5. Optional Reboot (recommended after upgrade)
# ------------------------------------------------------------
server_reboot_for_upgrade:
  cmd.run:
    - name: shutdown /r /t 60 /c "Reboot required to complete Windows Server edition upgrade"
    - shell: cmd
    - onlyif:
        - fun: cmd.run
          name: |
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -eq 'ServerDatacenter') { exit 0 } else { exit 1 }
          shell: powershell
    - require:
      - cmd: os_edition_activation