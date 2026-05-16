<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	3/7/2023 4:12 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Param (
	[string]$Path
)

Add-Type -TypeDefinition @"
    using System;
    using System.IO;
    using System.Security.AccessControl;

    public class FolderInfo {
        public string Name;
        public bool InheritanceEnabled;
        public bool HasExplicitAce;
    }

    public class FolderScanner {
        public static FolderInfo[] Scan(string path) {
            var folders = Directory.GetDirectories(path, "*", SearchOption.AllDirectories);
            var results = new FolderInfo[folders.Length];

            for (int i = 0; i < folders.Length; i++) {
                var folder = folders[i];
                var info = new FolderInfo();
                info.Name = folder;

                var acl = Directory.GetAccessControl(folder);
                info.InheritanceEnabled = acl.GetAccessRules(true, true, typeof(System.Security.Principal.NTAccount)).Count > 0;

                AuthorizationRuleCollection rules = acl.GetAccessRules(true, true, typeof(System.Security.Principal.NTAccount));
                foreach (FileSystemAccessRule rule in rules) {
                    if (rule.IsInherited == false) {
                        info.HasExplicitAce = true;
                        break;
                    }
                }

                if (!info.InheritanceEnabled || info.HasExplicitAce) {
                    results[i] = info;
                }
            }

            return results;
        }
    }
"@

$folderInfos = [FolderScanner]::Scan($Path) | Where-Object { $_ -ne $null }
$folderInfos
$folderInfos | gm
