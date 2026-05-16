Description:

Salt state to update the DNS resolvers on a Windows server. This script will check each NIC for the resolvers to see if one of the BAM servers is being used for name resolution. If it is, the resolves will be updated

## Detail:

This salt state will check to see if a Windows server requires the DNS settings update to facilitate the retirement of the BAM DNS servers

It will then run PowerShell script

```
FILES:
 * Update-DNSResolvers.ps1
```

see Jira: WIN-147
