{% if grains['os_family'] in ['Windows'] %}

set_dns_update_required:
  cmd.script:
    - name: salt://{{ slspath }}/files/test-ssncdns.ps1
    - template: jinja
    - shell: powershell
    - env:
      - ExecutionPolicy: "Unrestricted"

{% endif %}

