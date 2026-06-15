# ============================================================
# PILLAR: Windows Server Edition Upgrade - KMS Keys
# ============================================================
# ENCRYPTED PILLAR (use `salt-key -u` to manage encryption)
# Place in: /etc/salt/pillar/windows_server/upgrade.sls
# or reference in top.sls: 
#   windows_servers:
#     - windows_server.upgrade
# 
# To encrypt: salt-run pillar.show_top
# Command: salt 'target' pillar.items | grep kms

windows_server_upgrade:
  # KMS Keys by OS Version (encrypted in production)
  kms_keys:
    '2012':   'ENCRYPTED_KEY_PLACEHOLDER_2012'
    '2012R2': 'ENCRYPTED_KEY_PLACEHOLDER_2012R2'
    '2016':   'ENCRYPTED_KEY_PLACEHOLDER_2016'
    '2019':   'ENCRYPTED_KEY_PLACEHOLDER_2019'
    '2022':   'ENCRYPTED_KEY_PLACEHOLDER_2022'
    '2025':   'ENCRYPTED_KEY_PLACEHOLDER_2025'
  
  # Upgrade Configuration
  upgrade_config:
    target_edition: 'ServerDatacenter'
    reboot_delay_seconds: 300  # 5 minutes for graceful shutdown
    max_activation_retries: 3
    dism_log_path: 'C:\Windows\Logs\DISM\Server-Upgrade.log'
    
  # Notification settings (optional)
  notifications:
    send_alert_on_failure: True
    alert_recipients:
      - 'admin@company.com'
