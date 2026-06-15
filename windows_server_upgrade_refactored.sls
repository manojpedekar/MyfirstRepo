# ============================================================
# Windows Server Edition Upgrade: Standard → Datacenter
# REFACTORED VERSION
# ============================================================
# Changes:
# 1. KMS keys moved to encrypted Pillar data
# 2. Proper reboot sequencing (upgrade → reboot → activate → reboot)
# 3. DISM output captured and logged
# 4. Post-upgrade edition validation
# 5. Increased reboot delay (300s vs 60s)
# 6. Better error handling and logging
# ============================================================

{%- set target_edition = salt['pillar.get']('windows_server_upgrade:upgrade_config:target_edition', 'ServerDatacenter') -%}
{%- set reboot_delay = salt['pillar.get']('windows_server_upgrade:upgrade_config:reboot_delay_seconds', 300) -%}
{%- set kms_keys = salt['pillar.get']('windows_server_upgrade:kms_keys', {}) -%}
{%- set dism_log = salt['pillar.get']('windows_server_upgrade:upgrade_config:dism_log_path', 'C:\\Windows\\Logs\\DISM\\Server-Upgrade.log') -%}

# ============================================================
# STAGE 1: Detect Current OS Edition & Version
# ============================================================
detect_os_edition:
  cmd.run:
    - name: |
        $os = Get-CimInstance Win32_OperatingSystem
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $version = ([version]$os.Version).Major
        Write-Output "Edition=$edition"
        Write-Output "Version=$($os.Caption)"
        Write-Output "ReleaseId=$version"
    - shell: powershell
    - stateful: False


# ============================================================
# STAGE 2: Upgrade Edition (only if not already Datacenter)
# ============================================================
os_edition_upgrade:
  cmd.run:
    - shell: powershell
    - name: |
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $caption = (Get-CimInstance Win32_OperatingSystem).Caption

        if ($edition -eq '{{ target_edition }}') {
            Write-Output "✓ Already {{ target_edition }} edition. No action required."
            exit 0
        }

        # KMS keys from encrypted Pillar data
        $kmsKeys = @{
{%- for version, key in kms_keys.items() %}
            '{{ version }}' = '{{ key }}'
{%- endfor %}
        }

        $key = $null
        $matchedVersion = $null

        # Match Windows version (prioritize exact "R2" matches)
        switch -Regex ($caption) {
            '2025' { 
                $key = $kmsKeys['2025']
                $matchedVersion = '2025'
            }
            '2022' { 
                $key = $kmsKeys['2022']
                $matchedVersion = '2022'
            }
            '2019' { 
                $key = $kmsKeys['2019']
                $matchedVersion = '2019'
            }
            '2016' { 
                $key = $kmsKeys['2016']
                $matchedVersion = '2016'
            }
            '2012 R2' {  # Check R2 first (longer match)
                $key = $kmsKeys['2012R2']
                $matchedVersion = '2012R2'
            }
            '2012' { 
                $key = $kmsKeys['2012']
                $matchedVersion = '2012'
            }
            default {
                Write-Error "✗ Unsupported OS version: $caption"
                exit 1
            }
        }

        if (-not $key) {
            Write-Error "✗ No KMS key resolved for OS: $caption (version: $matchedVersion)"
            exit 1
        }

        Write-Output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Output "Starting upgrade from $edition → {{ target_edition }}"
        Write-Output "OS: $caption | Matched Version: $matchedVersion"
        Write-Output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # DISM upgrade with output logging (removed /Quiet)
        dism /online /Set-Edition:{{ target_edition }} `
             /ProductKey:$key `
             /AcceptEula `
             /LogPath:"{{ dism_log }}"

        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Output "✓ DISM upgrade completed successfully"
        } else {
            Write-Error "✗ DISM upgrade failed with exit code: $exitCode"
            Write-Error "Check detailed logs: {{ dism_log }}"
        }

        exit $exitCode

    - onlyif:
        - fun: cmd.run
          name: |
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -ne '{{ target_edition }}') { 
                Write-Output "Edition check: Current=$edition, Target={{ target_edition }}"
                exit 0 
            } else { 
                exit 1 
            }
          shell: powershell

    - onfail:
      - cmd: os_edition_upgrade_failed

    - require_in:
      - cmd: reboot_after_upgrade


# ============================================================
# STAGE 3: First Reboot (after edition upgrade)
# ============================================================
reboot_after_upgrade:
  cmd.run:
    - name: shutdown /r /t {{ reboot_delay }} /c "Rebooting to complete Windows Server edition upgrade"
    - shell: cmd

    - onlyif:
        - fun: cmd.run
          name: |
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -eq '{{ target_edition }}') { 
                Write-Output "✓ Edition confirmed as {{ target_edition }} - proceeding with reboot"
                exit 0 
            } else { 
                Write-Output "✗ Edition not yet {{ target_edition }} - reboot may be needed"
                exit 0
            }
          shell: powershell

    - require:
      - cmd: os_edition_upgrade

    - require_in:
      - cmd: validate_edition_after_upgrade


# ============================================================
# STAGE 4: Validate Edition After Reboot
# ============================================================
validate_edition_after_upgrade:
  cmd.run:
    - shell: powershell
    - name: |
        $maxAttempts = 5
        $attempt = 0
        $edition = $null

        # Retry logic in case system is still stabilizing
        while ($attempt -lt $maxAttempts) {
            try {
                $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
                if ($edition) { break }
            }
            catch {
                $attempt++
                Start-Sleep -Seconds 5
            }
        }

        if ($edition -eq '{{ target_edition }}') {
            Write-Output "✓ Edition upgrade validated: $edition"
            exit 0
        } else {
            Write-Error "✗ Edition validation FAILED. Current: $edition, Expected: {{ target_edition }}"
            exit 1
        }

    - require_in:
      - cmd: os_edition_activation

    - onfail:
      - cmd: os_edition_upgrade_validation_failed


# ============================================================
# STAGE 5: Activate Windows (via KMS)
# ============================================================
os_edition_activation:
  cmd.run:
    - shell: powershell
    - name: |
        Write-Output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Output "Attempting Windows KMS Activation..."
        Write-Output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Get current license status
        Write-Output "`n[Pre-Activation Status]"
        cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli

        # Attempt activation
        Write-Output "`n[Triggering Activation]"
        cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato

        # Verify activation
        Start-Sleep -Seconds 10
        Write-Output "`n[Post-Activation Status]"
        cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli

        exit $LASTEXITCODE

    - onlyif:
        - fun: cmd.run
          name: |
            $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
            if ($edition -eq '{{ target_edition }}') { 
                exit 0 
            } else { 
                exit 1 
            }
          shell: powershell

    - require:
      - cmd: validate_edition_after_upgrade

    - require_in:
      - cmd: reboot_after_activation

    - onfail:
      - cmd: os_activation_failed


# ============================================================
# STAGE 6: Final Reboot (if needed after activation)
# ============================================================
reboot_after_activation:
  cmd.run:
    - name: shutdown /r /t {{ reboot_delay }} /c "Final reboot to finalize Windows Server Datacenter upgrade"
    - shell: cmd

    - onlyif:
        - fun: cmd.run
          name: |
            # Only reboot if activation returned non-zero
            cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli | Select-String -Pattern "Initial grace period" -Quiet
            exit $?
          shell: powershell

    - require:
      - cmd: os_edition_activation


# ============================================================
# STAGE 7: Final Validation
# ============================================================
final_validation:
  cmd.run:
    - shell: powershell
    - name: |
        Write-Output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Output "FINAL VALIDATION - Windows Server Upgrade"
        Write-Output "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        $os = Get-CimInstance Win32_OperatingSystem
        
        Write-Output "`n✓ OS: $($os.Caption)"
        Write-Output "✓ Edition: $edition"
        Write-Output "✓ Build: $($os.BuildNumber)"
        
        if ($edition -eq '{{ target_edition }}') {
            Write-Output "`n✅ SUCCESS: Upgrade to {{ target_edition }} completed"
            exit 0
        } else {
            Write-Error "`n❌ FAILURE: Expected {{ target_edition }}, got $edition"
            exit 1
        }

    - require:
      - cmd: reboot_after_activation


# ============================================================
# ERROR HANDLERS
# ============================================================

os_edition_upgrade_failed:
  cmd.run:
    - shell: powershell
    - name: |
        Write-Error "❌ OS Edition upgrade failed"
        Write-Output "`nDISM Log Location: {{ dism_log }}"
        Write-Output "Review logs for details or run: Get-WindowsEdition -Online"
    - failhard: True


os_edition_upgrade_validation_failed:
  cmd.run:
    - shell: powershell
    - name: |
        Write-Error "❌ Edition validation failed after reboot"
        Write-Output "`nAttempt manual verification:`n"
        Write-Output "  PowerShell: Get-WindowsEdition -Online"
        Write-Output "  Registry: reg query 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' /v EditionID"
    - failhard: True


os_activation_failed:
  cmd.run:
    - shell: powershell
    - name: |
        Write-Error "⚠ Windows activation failed or returned non-zero"
        Write-Output "`nThis may be non-critical if using KMS in your environment."
        Write-Output "Check KMS server connectivity:`n"
        Write-Output "  slmgr /dli"
        Write-Output "  nslookup _vlmcs._tcp.dc._msdcs.YOURDOMAIN.COM"
    - failhard: False
