# Release Notes

Version history and changelog for the NTFS Permissions and AD Inventory tools.

## Current Version

**Version 1.8.0** - January 2026

## Version History

### Version 1.8.0 (January 2026)

**New Features:**
- Added AD Sites & Services collection (sites, subnets, site links)
- Added Domain Health collection (SYSVOL replication, GPO health)
- Added Optional Features collection (Recycle Bin, PAM, etc.)
- Trust relationship visualization in web interface
- Enhanced Domain Master List with forest/domain details

**Improvements:**
- Improved LDAP query performance for large directories
- Better error handling for cross-domain queries
- Enhanced progress reporting during collection
- Reduced memory usage for large NTFS collections

**Bug Fixes:**
- Fixed handling of single-element arrays in AD collection
- Fixed datetime sentinel values for never-expiring accounts
- Improved handling of special characters in folder names

---

### Version 1.7.0 (October 2025)

**New Features:**
- API upload support with API key authentication
- Background job processing with Hangfire
- Real-time upload progress via SignalR
- Collection logs viewable in web interface

**Improvements:**
- Streaming upload for large files (up to 3 GB)
- Improved ZIP validation with bomb detection
- Enhanced SQLite integrity checking

**Bug Fixes:**
- Fixed memory leak during large collections
- Improved handling of very long file paths
- Fixed duplicate detection during import

---

### Version 1.6.0 (July 2025)

**New Features:**
- Nested group membership flattening
- Foreign Security Principal resolution
- Enhanced trust relationship collection
- Export to CSV from web interface

**Improvements:**
- Parallel LDAP queries for faster collection
- Better handling of offline domain controllers
- Improved schema version compatibility

---

### Version 1.5.0 (April 2025)

**New Features:**
- AD Inventory collector (initial release)
- User, group, and computer collection
- Group membership collection
- Forest and domain configuration

**Improvements:**
- NTFS collector performance optimizations
- Better error messages
- Enhanced logging

---

### Version 1.4.0 (January 2025)

**New Features:**
- SMB share permission collection
- Volume and disk information
- Mount point support

**Improvements:**
- Reduced output file size
- Faster SQLite database creation

---

### Version 1.3.0 (October 2024)

**New Features:**
- MaxDepth parameter for limited collections
- Folder exclusion by name and path
- Quiet mode for scheduled tasks

**Bug Fixes:**
- Fixed handling of junction points
- Improved error recovery

---

### Version 1.2.0 (July 2024)

**New Features:**
- Inherited vs explicit permission tracking
- SID resolution to account names
- Collection resume capability

---

### Version 1.1.0 (April 2024)

**New Features:**
- Multiple path collection
- AllFixedDisks parameter
- Progress display improvements

---

### Version 1.0.0 (January 2024)

**Initial Release:**
- NTFS permission collection
- SQLite output format
- ZIP compression
- Basic web upload

---

## Upgrade Notes

### Upgrading to 1.8.0

1. Download the new collector from the web application
2. Replace your existing module folder
3. Re-import the module
4. No changes to existing collection scripts required

### Compatibility

- Collectors are backward-compatible with existing upload processes
- Web application automatically handles multiple collector versions
- Minimum supported collector version: 1.5.0

## Known Issues

### Current Known Issues

| Issue | Workaround | Status |
|-------|------------|--------|
| Very long paths (>260 chars) may be truncated | Use short output path | Investigating |
| Large AD forests (>1M objects) may timeout | Collect domains separately | Enhancement planned |

## Roadmap

Planned for future releases:

- [ ] Scheduled collection management in web UI
- [ ] Collection comparison reports
- [ ] PowerShell remoting support
- [ ] Linux file system support (experimental)

---

*For the latest version, always download from the web application.*
