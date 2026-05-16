using System.Runtime.Versioning;

namespace CLAWS.Core.Import;

/// <summary>
/// Value converter for NTFS Permissions databases.
/// Handles SID binary conversion and FileSystemRights bit preservation.
/// </summary>
[SupportedOSPlatform("windows")]
public class NtfsPermissionsValueConverter : DefaultValueConverter
{
    /// <inheritdoc/>
    public override object? Convert(object? value, ColumnInfo column)
    {
        if (value == null || value == DBNull.Value)
            return null;

        // Handle empty strings - call base for common handling
        if (value is string strValue && string.IsNullOrWhiteSpace(strValue))
        {
            var baseResult = base.Convert(value, column);
            if (baseResult == null)
                return null;
        }

        // Convert InventoryID to GUID
        if (column.Name.Equals("InventoryID", StringComparison.OrdinalIgnoreCase))
        {
            if (value is string strVal && Guid.TryParse(strVal, out var guid))
            {
                return guid;
            }
        }

        // Convert any column ending with _GUID to GUID type
        if (column.Name.EndsWith("_GUID", StringComparison.OrdinalIgnoreCase) && value is string guidStr)
        {
            if (Guid.TryParse(guidStr, out var parsedGuid))
            {
                return parsedGuid;
            }
            // If we can't parse it, return null
            return null;
        }

        // Convert SID string to binary
        // SIDs in SQLite are stored as strings like "S-1-5-32-544"
        // SQL Server expects varbinary
        if (column.Name.Equals("Sid", StringComparison.OrdinalIgnoreCase) && value is string sidString)
        {
            try
            {
                var sid = new System.Security.Principal.SecurityIdentifier(sidString);
                var binaryForm = new byte[sid.BinaryLength];
                sid.GetBinaryForm(binaryForm, 0);
                return binaryForm;
            }
            catch
            {
                // If SID parsing fails, return null
                return null;
            }
        }

        // Handle Int64 to Int32 conversion for columns that may have high bits set
        // FileSystemRights enum values can have high bits set (e.g., GENERIC_ALL = 0x10000000)
        // SQLite stores all integers as Int64, but SQL Server column may be int
        // We need to preserve the bit pattern when converting
        if (value is long int64Value)
        {
            // Check if this is a "Mask" or "Rights" column that should be Int32
            if (column.Name.Contains("Mask", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Contains("Rights", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Contains("Flags", StringComparison.OrdinalIgnoreCase))
            {
                // Convert preserving bit pattern (allows "negative" values when high bit is set)
                return unchecked((int)int64Value);
            }
        }

        // Return value as-is - let SQL Server handle type conversion
        return value;
    }
}
