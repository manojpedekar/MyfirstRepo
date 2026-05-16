## Description:

Salt state to test the DNS resolvers on a Windows server to see if one of the BAM servers is being used for name resolution.

## Detail:

This salt state will check to see if a Windows server requires the DNS settings update to facilitate the retirement of the BAM DNS servers

It will then run PowerShell script 

```
FILES:
 * test-ssncdns.ps1
```

see Jira:
WIN-147
