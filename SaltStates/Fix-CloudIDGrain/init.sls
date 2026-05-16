# Add a note here regarding the jira supporting this update

{% if grains['os_family'] == 'Windows' %}

add_domain_group:
  cmd.script:
    - name: salt://{{ slspath }}/files/Fix-CloudIDGrain.ps1
    - shell: powershell
    - hide_output: True
    - env:
      - ExecutionPolicy: "UnRestricted"

{% endif %}