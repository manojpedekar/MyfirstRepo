/**
 * @file TestNTFSPath.cpp
 * @brief NTFS Path Troubleshooting Tool
 *
 * This tool helps troubleshoot path access issues reported in CollectNTFSPerms
 * event logs. It tests if a specified path can be accessed and if its ACLs
 * can be retrieved.
 *
 * Now uses the shared PathUtils library for path handling and validation.
 *
 * Usage: TestNTFSPath <path_to_test> [--json] [--check-system] [--fix] [--fix-recursive]
 *
 * Exit codes:
 *   0  - Success (no issues detected)
 *   1  - Path does not exist
 *   2  - Access denied (cannot read directory)
 *   3  - ACL access denied (cannot read security descriptor)
 *   4  - SYSTEM account missing from ACL (with --check-system)
 *   5  - ACL is not in canonical order
 *   6  - Inheritance inconsistency detected (orphaned/missing inherited ACEs)
 *   7  - Fix operation failed
 *   10 - Invalid command-line arguments
 *   99 - Unknown error
 */

#include <iostream>
#include <string>
#include <vector>
#include <windows.h>

// Include shared PathUtils library
#include <PathUtils.h>
#include <PathValidator.h>

/**
 * @brief Gets the verdict color string for console output.
 */
std::wstring GetVerdictString(PathUtils::ValidationVerdict verdict) {
    switch (verdict) {
        case PathUtils::ValidationVerdict::Pass: return L"PASS";
        case PathUtils::ValidationVerdict::Warning: return L"WARNING";
        case PathUtils::ValidationVerdict::Fail: return L"FAIL";
        default: return L"UNKNOWN";
    }
}

/**
 * @brief Prints inheritance consistency analysis.
 */
void PrintInheritanceConsistency(const PathUtils::InheritanceConsistencyResult& consistency) {
    std::wcout << L"\nInheritance Consistency Check\n";
    std::wcout << L"-----------------------------\n";

    if (!consistency.success) {
        std::wcout << L"Could not check inheritance: " << consistency.errorMessage << L"\n";
        return;
    }

    std::wcout << L"Parent path: " << consistency.parentPath << L"\n";
    std::wcout << L"Inheritance enabled: " << (consistency.inheritanceEnabled ? L"Yes" : L"No") << L"\n";

    if (!consistency.inheritanceEnabled) {
        std::wcout << L"  (Inheritance is blocked - no consistency check needed)\n";
        return;
    }

    if (consistency.isConsistent) {
        std::wcout << L"Status: CONSISTENT - Inherited ACEs match parent's inheritable ACEs\n";
        return;
    }

    // Inconsistency detected!
    std::wcout << L"\n*** ACL INHERITANCE INCONSISTENCY DETECTED ***\n";
    std::wcout << L"\nThis indicates the security descriptor is corrupted, typically from:\n";
    std::wcout << L"  - Backup/restore that preserved ACLs from a different inheritance state\n";
    std::wcout << L"  - Folder moved (not copied) from a different location\n";
    std::wcout << L"  - Manual SDDL manipulation or third-party tool\n";

    // Show orphaned ACEs (would be DROPPED on fix)
    if (consistency.hasOrphanedAces()) {
        std::wcout << L"\nACEs marked as 'inherited' but NOT from parent (will be DROPPED on fix):\n";
        std::wcout << L"  -------------------------------------------------------------------------\n";
        for (const auto& ace : consistency.orphanedInheritedAces) {
            std::wcout << L"  [DROP] " << ace.getTypeString() << L" - ";
            std::wcout << ace.getDisplayName();
            std::wcout << L" : " << ace.getAccessMaskString();
            std::wcout << L" [" << ace.getInheritanceFlagsString() << L"]\n";
        }
    }

    // Show missing ACEs (would be ADDED on fix)
    if (consistency.hasMissingAces()) {
        std::wcout << L"\nACEs in parent that SHOULD inherit but are missing (will be ADDED on fix):\n";
        std::wcout << L"  -------------------------------------------------------------------------\n";
        for (const auto& ace : consistency.missingInheritedAces) {
            std::wcout << L"  [ADD]  " << ace.getTypeString() << L" - ";
            std::wcout << ace.getDisplayName();
            std::wcout << L" : " << ace.getAccessMaskString();
            std::wcout << L" [" << ace.getInheritanceFlagsString() << L"]\n";
        }
    }

    std::wcout << L"\nTo fix this issue, run: TestNTFSPath \"<path>\" --fix\n";
    std::wcout << L"To fix recursively:    TestNTFSPath \"<path>\" --fix-recursive\n";
}

/**
 * @brief Prints text-format validation results to console.
 */
void PrintTextOutput(const PathUtils::PathValidationResult& result,
                     const PathUtils::AclAnalysisResult& aclAnalysis,
                     const PathUtils::InheritanceConsistencyResult& consistency,
                     bool checkSystem) {
    std::wcout << L"\n==================================================\n";
    std::wcout << L"NTFS Path Troubleshooting Tool\n";
    std::wcout << L"==================================================\n\n";

    // Summary/Verdict at the top
    auto verdict = result.getVerdict();

    // Upgrade verdict based on ACL analysis
    if (verdict == PathUtils::ValidationVerdict::Pass && aclAnalysis.success) {
        if (!aclAnalysis.areAccessRulesCanonical) {
            verdict = PathUtils::ValidationVerdict::Warning;
        }
        if (checkSystem && !aclAnalysis.systemHasAccess && !aclAnalysis.isNullDacl) {
            verdict = PathUtils::ValidationVerdict::Warning;
        }
        if (consistency.success && !consistency.isConsistent) {
            verdict = PathUtils::ValidationVerdict::Warning;
        }
    }

    std::wcout << L"VERDICT: " << GetVerdictString(verdict) << L"\n";
    std::wcout << L"Path: " << result.path << L"\n\n";

    // Path Information
    std::wcout << L"Path Information\n";
    std::wcout << L"----------------\n";
    std::wcout << L"Path exists: " << (result.exists ? L"Yes" : L"No") << L"\n";

    if (result.exists) {
        std::wcout << L"Is directory: " << (result.isDirectory ? L"Yes" : L"No") << L"\n";

        // File System Info
        if (!result.fsInfo.fileSystemName.empty()) {
            std::wcout << L"File system: " << result.fsInfo.fileSystemName;
            if (!result.fsInfo.volumeName.empty()) {
                std::wcout << L" (Volume: " << result.fsInfo.volumeName << L")";
            }
            std::wcout << L"\n";
            std::wcout << L"  Supports ACLs: " << (result.fsInfo.supportsAcls ? L"Yes" : L"No") << L"\n";
        }

        // Reparse Point Info
        if (result.reparseType != PathUtils::ReparsePointType::None) {
            std::wcout << L"Reparse point: " << PathUtils::getReparsePointTypeString(result.reparseType) << L"\n";
        }

        std::wcout << L"Attributes: ";
        if (result.attributes.readonly) std::wcout << L"ReadOnly ";
        if (result.attributes.hidden) std::wcout << L"Hidden ";
        if (result.attributes.system) std::wcout << L"System ";
        if (result.attributes.archive) std::wcout << L"Archive ";
        if (result.attributes.compressed) std::wcout << L"Compressed ";
        if (result.attributes.encrypted) std::wcout << L"Encrypted ";
        if (result.attributes.reparsePoint) std::wcout << L"ReparsePoint ";
        if (result.attributes.sparse) std::wcout << L"Sparse ";
        if (result.attributes.offline) std::wcout << L"Offline ";
        std::wcout << L"\n";
    }

    std::wcout << L"Path length: " << result.pathLength << L" characters\n";
    if (result.exceedsMaxPath) {
        std::wcout << L"WARNING: Path exceeds Windows API MAX_PATH limit (260 characters)\n";
    }

    // Folder Scanner Test
    std::wcout << L"\nFolderScanner Test (Directory Listing)\n";
    std::wcout << L"------------------------------------\n";
    std::wcout << L"Can list directory contents: " << (result.accessResult.success ? L"Yes" : L"No") << L"\n";

    if (!result.accessResult.success) {
        std::wcout << L"Error: " << result.accessResult.errorMessage << L"\n";

        if (result.accessResult.isAccessDenied()) {
            std::wcout << L"Diagnosis: Access denied. This could be due to insufficient permissions.\n";
            std::wcout << L"           CollectNTFSPerms may need to run with elevated privileges.\n";
        } else if (result.accessResult.isNotFound()) {
            std::wcout << L"Diagnosis: Path not found. Verify the path exists and is spelled correctly.\n";
        } else if (result.accessResult.isInvalidName()) {
            std::wcout << L"Diagnosis: Invalid path name. Check for illegal characters or format.\n";
        } else if (result.accessResult.isNetworkError()) {
            std::wcout << L"Diagnosis: Network error. Verify the server is reachable and share name is correct.\n";
        }
    }

    // ACL Processor Test
    std::wcout << L"\nAclProcessor Test (Security Descriptor Retrieval)\n";
    std::wcout << L"----------------------------------------------\n";

    if (!result.exists) {
        std::wcout << L"Cannot test ACL retrieval: Path does not exist\n";
    } else {
        std::wcout << L"Can retrieve security descriptor: " << (result.aclResult.success ? L"Yes" : L"No") << L"\n";

        if (!result.aclResult.success) {
            std::wcout << L"Error: " << result.aclResult.errorMessage << L"\n";

            if (result.aclResult.errorCode == ERROR_ACCESS_DENIED) {
                std::wcout << L"Diagnosis: Access denied when retrieving ACL. This could indicate\n";
                std::wcout << L"           that the current user lacks permission to read security information.\n";
            }
        } else {
            std::wcout << L"DACL present: " << (result.aclResult.daclPresent ? L"Yes" : L"No") << L"\n";
            std::wcout << L"DACL defaulted: " << (result.aclResult.daclDefaulted ? L"Yes" : L"No") << L"\n";
            std::wcout << L"ACE count: " << result.aclResult.aceCount << L"\n";

            if (!result.aclResult.sddl.empty()) {
                std::wcout << L"Security Descriptor (SDDL format): " << result.aclResult.sddl << L"\n";
            }

            // Detailed ACL analysis
            std::wcout << L"\nDetailed ACL Analysis\n";
            std::wcout << L"--------------------\n";

            if (aclAnalysis.success) {
                // Owner and Group
                std::wcout << L"Owner: " << (aclAnalysis.ownerName.empty() ? aclAnalysis.ownerSid : aclAnalysis.ownerName);
                if (!aclAnalysis.ownerName.empty() && !aclAnalysis.ownerSid.empty()) {
                    std::wcout << L" (" << aclAnalysis.ownerSid << L")";
                }
                std::wcout << L"\n";

                std::wcout << L"Group: " << (aclAnalysis.groupName.empty() ? aclAnalysis.groupSid : aclAnalysis.groupName);
                if (!aclAnalysis.groupName.empty() && !aclAnalysis.groupSid.empty()) {
                    std::wcout << L" (" << aclAnalysis.groupSid << L")";
                }
                std::wcout << L"\n\n";

                // NULL DACL check
                if (aclAnalysis.isNullDacl) {
                    std::wcout << L"WARNING: NULL DACL detected - everyone has full control!\n\n";
                }

                // Protection and Canonical flags
                std::wcout << L"AreAccessRulesProtected : " << (aclAnalysis.areAccessRulesProtected ? L"True" : L"False");
                if (aclAnalysis.areAccessRulesProtected) {
                    std::wcout << L" (inheritance blocked)";
                }
                std::wcout << L"\n";

                std::wcout << L"AreAuditRulesProtected  : " << (aclAnalysis.areAuditRulesProtected ? L"True" : L"False") << L"\n";
                std::wcout << L"AreAccessRulesCanonical : " << (aclAnalysis.areAccessRulesCanonical ? L"True" : L"False");
                if (!aclAnalysis.areAccessRulesCanonical) {
                    std::wcout << L" (WARNING: non-canonical order!)";
                }
                std::wcout << L"\n";
                std::wcout << L"AreAuditRulesCanonical  : " << (aclAnalysis.areAuditRulesCanonical ? L"True" : L"False") << L"\n";

                // SYSTEM access check
                if (checkSystem) {
                    std::wcout << L"\nSYSTEM Access Check:\n";
                    if (aclAnalysis.isNullDacl) {
                        std::wcout << L"  SYSTEM has access: Yes (NULL DACL - everyone has access)\n";
                    } else {
                        std::wcout << L"  SYSTEM has access: " << (aclAnalysis.systemHasAccess ? L"Yes" : L"NO - WARNING!") << L"\n";
                        if (!aclAnalysis.systemHasAccess) {
                            std::wcout << L"  The SYSTEM account (S-1-5-18) is not granted explicit access.\n";
                            std::wcout << L"  This may prevent system services from accessing this folder.\n";
                        }
                    }
                }

                // ACE counts
                std::wcout << L"\nACE Summary:\n";
                std::wcout << L"  Total ACEs    : " << aclAnalysis.totalAceCount << L"\n";
                std::wcout << L"  Inherited     : " << aclAnalysis.inheritedAceCount << L"\n";
                std::wcout << L"  Explicit      : " << aclAnalysis.explicitAceCount << L"\n";

                // List all ACEs with inheritance flags
                if (!aclAnalysis.aces.empty()) {
                    std::wcout << L"\nAccess Control Entries:\n";
                    std::wcout << L"  #  Type   Inherit   Principal                                  Permissions        Flags\n";
                    std::wcout << L"  -----------------------------------------------------------------------------------------\n";

                    for (size_t i = 0; i < aclAnalysis.aces.size(); i++) {
                        const auto& ace = aclAnalysis.aces[i];

                        // Index
                        wchar_t indexBuf[8];
                        swprintf_s(indexBuf, L"%2zu", i);
                        std::wcout << L"  " << indexBuf << L" ";

                        // Type (padded to 6 chars)
                        std::wstring typeStr = ace.getTypeString();
                        std::wcout << typeStr;
                        for (size_t j = typeStr.length(); j < 7; j++) std::wcout << L" ";

                        // Inherit status (padded to 10 chars)
                        std::wstring inheritStr = ace.isInherited ? L"Inherited" : L"Explicit";
                        std::wcout << inheritStr;
                        for (size_t j = inheritStr.length(); j < 10; j++) std::wcout << L" ";

                        // Principal (padded to 42 chars)
                        std::wstring principal = ace.getDisplayName();
                        if (principal.length() > 40) {
                            principal = principal.substr(0, 37) + L"...";
                        }
                        std::wcout << principal;
                        for (size_t j = principal.length(); j < 42; j++) std::wcout << L" ";

                        // Permissions (padded to 18 chars)
                        std::wstring perms = ace.getAccessMaskString();
                        if (perms.length() > 16) {
                            perms = perms.substr(0, 13) + L"...";
                        }
                        std::wcout << perms;
                        for (size_t j = perms.length(); j < 19; j++) std::wcout << L" ";

                        // Inheritance flags
                        std::wcout << ace.getInheritanceFlagsString();

                        std::wcout << L"\n";
                    }

                    // Legend for inheritance flags
                    std::wcout << L"\n  Flags: CI=Container Inherit, OI=Object Inherit, IO=Inherit Only, NP=No Propagate\n";
                }

                // Inheritance Consistency Check - this is the key new feature
                PrintInheritanceConsistency(consistency);

            } else {
                std::wcout << L"ACL analysis failed: " << aclAnalysis.errorMessage << L"\n";
            }
        }
    }

    // Long Path Test
    std::wcout << L"\nLong Path Handling Test\n";
    std::wcout << L"---------------------\n";
    std::wcout << L"Long path format: " << result.longPath << L"\n";
    std::wcout << L"Long path access: " << (result.longPathWorks ? L"Successful" : L"Failed") << L"\n";

    if (!result.longPathWorks) {
        std::wcout << L"Error: " << result.longPathErrorMsg << L"\n";
    }

    // Recommendations
    std::wcout << L"\nRecommendations for CollectNTFSPerms\n";
    std::wcout << L"----------------------------------\n";

    auto recommendations = result.getRecommendations();
    for (const auto& rec : recommendations) {
        std::wcout << L"- " << rec << L"\n";
    }

    std::wcout << L"\n";
}

/**
 * @brief Prints usage information.
 */
void PrintUsage() {
    std::wcout << L"Usage: TestNTFSPath <path_to_test> [options]\n\n";
    std::wcout << L"Purpose: This tool helps troubleshoot path access issues reported in\n";
    std::wcout << L"         CollectNTFSPerms event logs. It tests if the specified path\n";
    std::wcout << L"         can be accessed and if its ACLs can be retrieved.\n\n";
    std::wcout << L"Options:\n";
    std::wcout << L"  --json           Output results in JSON format\n";
    std::wcout << L"  --check-system   Check if SYSTEM account has access to the path\n";
    std::wcout << L"  --fix            Fix inheritance by recalculating from parent\n";
    std::wcout << L"  --fix-recursive  Fix inheritance recursively for all children\n";
    std::wcout << L"  --addsystem      Add SYSTEM account with Full Control (only if inheritance blocked)\n\n";
    std::wcout << L"Exit codes:\n";
    std::wcout << L"  0  - Success (no issues detected)\n";
    std::wcout << L"  1  - Path does not exist\n";
    std::wcout << L"  2  - Access denied (cannot read directory)\n";
    std::wcout << L"  3  - ACL access denied (cannot read security descriptor)\n";
    std::wcout << L"  4  - SYSTEM account missing from ACL (with --check-system)\n";
    std::wcout << L"  5  - ACL is not in canonical order\n";
    std::wcout << L"  6  - Inheritance inconsistency detected\n";
    std::wcout << L"  7  - Fix operation failed\n";
    std::wcout << L"  10 - Invalid command-line arguments\n";
    std::wcout << L"  99 - Unknown error\n\n";
    std::wcout << L"Examples:\n";
    std::wcout << L"  TestNTFSPath.exe \"C:\\Folder\" --check-system\n";
    std::wcout << L"  TestNTFSPath.exe \"C:\\Folder\" --fix\n";
    std::wcout << L"  TestNTFSPath.exe \"C:\\Folder\" --fix-recursive\n";
    std::wcout << L"  TestNTFSPath.exe \"C:\\Folder\" --addsystem\n";
}

/**
 * @brief Determines the appropriate exit code based on validation results.
 */
int GetExitCode(const PathUtils::PathValidationResult& result,
                const PathUtils::AclAnalysisResult& aclAnalysis,
                const PathUtils::InheritanceConsistencyResult& consistency,
                bool checkSystem) {
    // Basic exit code from path validation
    auto exitCode = result.getExitCode();

    if (exitCode != PathUtils::ExitCode::Success) {
        return static_cast<int>(exitCode);
    }

    // Additional checks from ACL analysis
    if (aclAnalysis.success) {
        if (checkSystem && !aclAnalysis.systemHasAccess && !aclAnalysis.isNullDacl) {
            return static_cast<int>(PathUtils::ExitCode::SystemMissing);
        }
        if (!aclAnalysis.areAccessRulesCanonical) {
            return static_cast<int>(PathUtils::ExitCode::NonCanonical);
        }
    }

    // Check inheritance consistency
    if (consistency.success && !consistency.isConsistent) {
        return static_cast<int>(PathUtils::ExitCode::InheritanceIssue);
    }

    return static_cast<int>(PathUtils::ExitCode::Success);
}

/**
 * @brief Performs the fix operation and displays results.
 */
int PerformFix(const std::wstring& path, bool recursive,
               const PathUtils::InheritanceConsistencyResult& consistency) {

    std::wcout << L"\n==================================================\n";
    std::wcout << L"Fixing Inheritance for: " << path << L"\n";
    std::wcout << L"==================================================\n\n";

    // Show what will happen
    if (consistency.success && !consistency.isConsistent) {
        if (consistency.hasOrphanedAces()) {
            std::wcout << L"The following ACEs will be REMOVED:\n";
            for (const auto& ace : consistency.orphanedInheritedAces) {
                std::wcout << L"  - " << ace.getTypeString() << L" - ";
                std::wcout << ace.getDisplayName();
                std::wcout << L" : " << ace.getAccessMaskString() << L"\n";
            }
            std::wcout << L"\n";
        }

        if (consistency.hasMissingAces()) {
            std::wcout << L"The following ACEs will be ADDED:\n";
            for (const auto& ace : consistency.missingInheritedAces) {
                std::wcout << L"  + " << ace.getTypeString() << L" - ";
                std::wcout << ace.getDisplayName();
                std::wcout << L" : " << ace.getAccessMaskString() << L"\n";
            }
            std::wcout << L"\n";
        }
    } else {
        std::wcout << L"No inheritance inconsistencies detected, but will reset anyway.\n";
        std::wcout << L"This will recalculate inherited ACEs from the parent.\n\n";
    }

    std::wcout << L"Executing fix" << (recursive ? L" (recursive)" : L"") << L"...\n";

    auto fixResult = PathUtils::fixInheritance(path, recursive);

    std::wcout << L"Command: " << fixResult.commandUsed << L"\n\n";

    if (fixResult.success) {
        std::wcout << L"SUCCESS: Inheritance has been recalculated.\n";

        // Re-analyze to show new state
        std::wcout << L"\nVerifying new ACL state...\n";
        auto newAclAnalysis = PathUtils::analyzeAcl(path);

        if (newAclAnalysis.success) {
            std::wcout << L"\nNew ACE count: " << newAclAnalysis.totalAceCount << L"\n";
            std::wcout << L"  Inherited: " << newAclAnalysis.inheritedAceCount << L"\n";
            std::wcout << L"  Explicit:  " << newAclAnalysis.explicitAceCount << L"\n";

            if (!newAclAnalysis.aces.empty()) {
                std::wcout << L"\nNew Access Control Entries:\n";
                for (size_t i = 0; i < newAclAnalysis.aces.size(); i++) {
                    const auto& ace = newAclAnalysis.aces[i];
                    std::wcout << L"  [" << i << L"] ";
                    std::wcout << (ace.isInherited ? L"(Inherited) " : L"(Explicit)  ");
                    std::wcout << ace.getTypeString() << L" - ";
                    std::wcout << ace.getDisplayName();
                    std::wcout << L" : " << ace.getAccessMaskString() << L"\n";
                }
            }
        }

        return 0;
    } else {
        std::wcout << L"FAILED: " << fixResult.errorMessage << L"\n";
        std::wcout << L"\nTroubleshooting:\n";
        std::wcout << L"  - Ensure you are running as Administrator\n";
        std::wcout << L"  - Check that you have permission to modify security on this path\n";
        std::wcout << L"  - Verify the path is not read-only or locked\n";
        return 7;
    }
}

/**
 * @brief Performs the add SYSTEM operation and displays results.
 */
int PerformAddSystem(const std::wstring& path) {

    std::wcout << L"\n==================================================\n";
    std::wcout << L"Adding SYSTEM Account to: " << path << L"\n";
    std::wcout << L"==================================================\n\n";

    auto addResult = PathUtils::addSystemAce(path);

    if (addResult.inheritanceWasEnabled) {
        std::wcout << L"NOTICE: Inheritance is ENABLED on this folder.\n";
        std::wcout << L"\n";
        std::wcout << L"When inheritance is enabled, SYSTEM should automatically inherit\n";
        std::wcout << L"permissions from the parent folder. Adding an explicit SYSTEM ACE\n";
        std::wcout << L"is not necessary and may cause confusion.\n";
        std::wcout << L"\n";
        std::wcout << L"If SYSTEM is missing despite inheritance being enabled, this indicates\n";
        std::wcout << L"an ACL inconsistency. Use --fix to recalculate inheritance from parent.\n";
        std::wcout << L"\n";
        std::wcout << L"No action taken.\n";
        return 0;
    }

    if (addResult.systemAlreadyPresent) {
        std::wcout << L"SYSTEM account already has access to this folder.\n";
        std::wcout << L"No action needed.\n";
        return 0;
    }

    if (addResult.success) {
        std::wcout << L"SUCCESS: Added SYSTEM account with Full Control.\n";
        std::wcout << L"         Inheritance flags: ContainerInherit, ObjectInherit\n";

        // Re-analyze to show new state
        std::wcout << L"\nVerifying new ACL state...\n";
        auto newAclAnalysis = PathUtils::analyzeAcl(path);

        if (newAclAnalysis.success) {
            std::wcout << L"\nNew ACE count: " << newAclAnalysis.totalAceCount << L"\n";
            std::wcout << L"SYSTEM has access: " << (newAclAnalysis.systemHasAccess ? L"Yes" : L"No") << L"\n";

            if (!newAclAnalysis.aces.empty()) {
                std::wcout << L"\nNew Access Control Entries:\n";
                for (size_t i = 0; i < newAclAnalysis.aces.size(); i++) {
                    const auto& ace = newAclAnalysis.aces[i];
                    std::wcout << L"  [" << i << L"] ";
                    std::wcout << (ace.isInherited ? L"(Inherited) " : L"(Explicit)  ");
                    std::wcout << ace.getTypeString() << L" - ";
                    std::wcout << ace.getDisplayName();
                    std::wcout << L" : " << ace.getAccessMaskString();
                    std::wcout << L" [" << ace.getInheritanceFlagsString() << L"]\n";
                }
            }
        }

        return 0;
    } else {
        std::wcout << L"FAILED: " << addResult.errorMessage << L"\n";
        std::wcout << L"\nTroubleshooting:\n";
        std::wcout << L"  - Ensure you are running as Administrator\n";
        std::wcout << L"  - Check that you have permission to modify security on this path\n";
        std::wcout << L"  - Verify the path is not read-only or locked\n";
        return 7;
    }
}

int main(int argc, char* argv[])
{
    bool useJsonOutput = false;
    bool checkSystem = false;
    bool doFix = false;
    bool doFixRecursive = false;
    bool doAddSystem = false;
    std::string pathArg;

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--json") {
            useJsonOutput = true;
        } else if (arg == "--check-system") {
            checkSystem = true;
        } else if (arg == "--fix") {
            doFix = true;
        } else if (arg == "--fix-recursive") {
            doFix = true;
            doFixRecursive = true;
        } else if (arg == "--addsystem") {
            doAddSystem = true;
        } else if (arg == "--help" || arg == "-h" || arg == "/?") {
            PrintUsage();
            return 0;
        } else if (pathArg.empty()) {
            pathArg = arg;
        }
    }

    // Check if a path was provided
    if (pathArg.empty()) {
        if (useJsonOutput) {
            std::wcout << L"{\"error\": \"No path provided\", \"exitCode\": 10}\n";
            return static_cast<int>(PathUtils::ExitCode::ArgumentError);
        } else {
            PrintUsage();
            return static_cast<int>(PathUtils::ExitCode::ArgumentError);
        }
    }

    // Convert command line argument to wide string using PathUtils
    std::wstring pathToTest = PathUtils::toWideFromAcp(pathArg);

    // Remove surrounding quotes if present
    if (!pathToTest.empty() && pathToTest.front() == L'"' && pathToTest.back() == L'"') {
        pathToTest = pathToTest.substr(1, pathToTest.size() - 2);
    }

    // Remove trailing backslash unless it's a root path (e.g., "C:\" or "\\server\share\")
    if (!pathToTest.empty() && (pathToTest.back() == L'\\' || pathToTest.back() == L'/')) {
        bool isRoot = false;

        // Check for local drive root (e.g., "C:\")
        if (pathToTest.length() == 3 && pathToTest[1] == L':') {
            isRoot = true;
        }
        // Check for UNC share root (e.g., "\\server\share\")
        else if (pathToTest.length() >= 5 && pathToTest[0] == L'\\' && pathToTest[1] == L'\\') {
            // Count backslashes after the initial "\\"
            // UNC root has format: \\server\share\ (exactly 2 components after \\)
            size_t backslashCount = 0;
            for (size_t i = 2; i < pathToTest.length() - 1; ++i) {
                if (pathToTest[i] == L'\\') {
                    ++backslashCount;
                }
            }
            // If there's exactly one backslash after \\, this is a UNC root
            // (separating server from share, with trailing slash)
            if (backslashCount == 1) {
                isRoot = true;
            }
        }

        if (!isRoot) {
            pathToTest.pop_back();
        }
    }

    // Perform comprehensive path validation using PathUtils
    auto result = PathUtils::validatePath(pathToTest);

    // Perform detailed ACL analysis
    PathUtils::AclAnalysisResult aclAnalysis;
    if (result.exists && result.aclResult.success) {
        aclAnalysis = PathUtils::analyzeAcl(pathToTest);
    }

    // Perform inheritance consistency check
    PathUtils::InheritanceConsistencyResult consistency;
    if (result.exists && result.aclResult.success && aclAnalysis.success) {
        consistency = PathUtils::checkInheritanceConsistency(pathToTest);
    }

    // If --fix was requested, perform the fix operation
    if (doFix) {
        return PerformFix(pathToTest, doFixRecursive, consistency);
    }

    // If --addsystem was requested, perform the add SYSTEM operation
    if (doAddSystem) {
        return PerformAddSystem(pathToTest);
    }

    // Determine exit code
    int exitCode = GetExitCode(result, aclAnalysis, consistency, checkSystem);

    // Output results
    if (useJsonOutput) {
        std::wcout << PathUtils::toJson(result) << L"\n";
    } else {
        PrintTextOutput(result, aclAnalysis, consistency, checkSystem);
    }

    return exitCode;
}
