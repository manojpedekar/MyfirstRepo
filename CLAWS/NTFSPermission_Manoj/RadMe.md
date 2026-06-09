Examples:
# Discover shares on the local machine
.\Batch-CollectNTFSPerms.ps1

# Discover shares on a remote server
.\Batch-CollectNTFSPerms.ps1 -Server "FILESERVER01"

# Still works with a manual CSV if needed
.\Batch-CollectNTFSPerms.ps1 -CsvPath "C:\temp\folders.csv"

# Override output folder
.\Batch-CollectNTFSPerms.ps1 -Server "FILESERVER01" -OutputDir "D:\Audits"

Auto-discovery (default) — runs the WMI query at startup, pulls the Path property from every Type=0 share, and feeds those directly into the processing loop. No CSV needed.
Remote server support — pass -Server "FILESERVER01" and WMI queries that machine instead of localhost. Useful if you're running the script from your workstation against a file server.
CSV fallback still works — if you pass -CsvPath, it ignores WMI entirely and behaves like the original script. Handy if you ever need to target a specific subset.