# Salt State for Windows Server OS Edition Upgrade (Standard to Datacenter)
# Usage: salt 'target_servers' state.apply win_upgrade_datacenter
# Local usage: salt-call --local state.apply win_upgrade_datacenter

# Jinja variables for KMS GVLK keys
{%- set kms_keys = {
    '2012': 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9',
    '2012R2': 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9',
    '2016': 'CB7KF-BWN84-R7R2Y-793K2-8XDDG',
    '2019': 'WMDGN-G9PQG-XVVXX-R3X43-63DFG',
    '2022': 'WX4NM-KYWYW-QJJR4-XV3QB-6VM33',
    '2025': 'D764K-2NDRG-47T6Q-P8T8W-YP6DF'
} -%}

# Detect current OS version and edition
check_os_edition:
  cmd.run:
    - name: |
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $caption = (Get-CimInstance Win32_OperatingSystem).Caption
        Write-Output "CurrentEdition: $edition`nOSCaption: $caption"
    - shell: powershell
    - stateful: False

# Skip if already Datacenter
{%- set grains_data = salt['cmd.run']('Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" | Select-Object -ExpandProperty EditionID', shell='powershell') -%}

# Upgrade OS Edition to Datacenter
os_edition_upgrade:
  cmd.run:
    - name: |
        $caption = (Get-CimInstance Win32_OperatingSystem).Caption
        $currentEdition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        
        if ($currentEdition -eq 'ServerDatacenter') {
            Write-Output 'Already Datacenter edition. Skipping upgrade.'
            exit 0
        }
        
        # Map OS version to KMS key
        $kmsKeys = @{
            '2012'   = '48HP8-DN98B-MYWDG-T2DCC-8W83P'
            '2012R2' = 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9'
            '2016'   = 'CB7KF-BWN84-R7R2Y-793K2-8XDDG'
            '2019'   = 'WMDGN-G9PQG-XVVXX-R3X43-63DFG'
            '2022'   = 'WX4NM-KYWYW-QJJR4-XV3QB-6VM33'
            '2025'   = 'D764K-2NDRG-47T6Q-P8T8W-YP6DF'
        }
        
        $key = $null
        switch -Regex ($caption) {
            '2012 R2' { $key = $kmsKeys['2012R2']; break }
            '2012'    { $key = $kmsKeys['2012']; break }
            '2016'    { $key = $kmsKeys['2016']; break }
            '2019'    { $key = $kmsKeys['2019']; break }
            '2022'    { $key = $kmsKeys['2022']; break }
            '2025'    { $key = $kmsKeys['2025']; break }
            default   { Write-Error "Unsupported OS version: $caption"; exit 1 }
        }
        
        if ($null -eq $key) {
            Write-Error "Could not determine appropriate KMS key for: $caption"
            exit 1
        }
        
        Write-Output "Upgrading $currentEdition to ServerDatacenter on $caption..."
        dism /online /Set-Edition:ServerDatacenter /ProductKey:$key /AcceptEula /Quiet /NoRestart
        
        exit $LASTEXITCODE
    - shell: powershell
    - onfail:
      - cmd: os_edition_upgrade_failed
    - onchanges:
      - cmd: os_edition_activation

# Activate license after upgrade
os_edition_activation:
  cmd.run:
    - name: cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato
    - shell: powershell
    - require:
      - cmd: os_edition_upgrade
    - onlyif:
      - fun: cmd.run
        name: |
          $exitCode = 0
          try {
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -ne 'ServerDatacenter') { exit 1 }
          } catch { exit 1 }
        shell: powershell

# Failure handler
os_edition_upgrade_failed:
  cmd.run:
    - name: Write-Error "OS edition upgrade failed on this server"
    - shell: powershell
    - failhard: True

# Optional: Reboot server to finalize (uncomment if immediate reboot is required)
# server_reboot_for_upgrade:
#   cmd.run:
#     - name: shutdown /r /t 30 /c "Windows Server edition upgraded to Datacenter. Rebooting to complete upgrade."
#     - require:
#       - cmd: os_edition_upgrade
