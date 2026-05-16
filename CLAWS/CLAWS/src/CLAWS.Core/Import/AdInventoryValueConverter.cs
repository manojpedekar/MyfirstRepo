namespace CLAWS.Core.Import;

/// <summary>
/// Value converter for ADInventory databases with GUID schema.
/// Converts TEXT GUID strings from SQLite to native Guid for SQL Server UNIQUEIDENTIFIER columns.
/// ADInventory databases store SIDs as text strings (no binary conversion needed).
/// </summary>
public class AdInventoryValueConverter : DefaultValueConverter
{
    /// <summary>
    /// Columns that contain GUID values stored as TEXT in SQLite.
    /// These are converted to native Guid for SQL Server UNIQUEIDENTIFIER columns.
    /// </summary>
    private static readonly HashSet<string> GuidColumns = new(StringComparer.OrdinalIgnoreCase)
    {
        "CollectionID",
        "InventoryID",
        "ObjectGUID",
        "DomainGUID",
        "ForestGUID",
        "FeatureGUID",      // AD_OptionalFeature
        "InvocationId"      // AD_DomainController
    };

    /// <inheritdoc/>
    public override object? Convert(object? value, ColumnInfo column)
    {
        if (value == null || value == DBNull.Value)
            return null;

        // Handle GUID columns - parse TEXT to native Guid for UNIQUEIDENTIFIER columns
        if (GuidColumns.Contains(column.Name))
        {
            if (value is string strVal && !string.IsNullOrWhiteSpace(strVal))
            {
                if (Guid.TryParse(strVal, out var guidValue))
                    return guidValue;
            }
            return null;
        }

        // Handle empty strings for DateTime columns
        if (value is string strValue && string.IsNullOrWhiteSpace(strValue))
        {
            if (column.Name.EndsWith("Date", StringComparison.OrdinalIgnoreCase) ||
                column.Name.EndsWith("DateTime", StringComparison.OrdinalIgnoreCase) ||
                column.Name.EndsWith("Time", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("WhenCreated", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("WhenChanged", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("LastLogonTimestamp", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("PasswordLastSet", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("AccountExpires", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("LastResolveAttempt", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }
        }

        // Handle datetime parsing from ISO 8601 strings
        // ADInventory stores dates as ISO 8601 text
        if (IsDateTimeColumn(column.Name) && value is string dateStr && !string.IsNullOrWhiteSpace(dateStr))
        {
            if (DateTime.TryParse(dateStr, out var parsedDate))
            {
                return parsedDate;
            }
            // Return null if parsing fails
            return null;
        }

        // Handle boolean columns (stored as 0/1 in SQLite)
        if (IsBooleanColumn(column.Name) && value is long longValue)
        {
            return longValue != 0;
        }

        // SID_String columns - pass through as text (no binary conversion)
        // ADInventory uses text SIDs like "S-1-5-21-..."

        // JSON columns (SIDHistory, PathToMember, Context, ChildDomains, etc.) - pass through
        // These are stored as nvarchar(max) in SQL Server

        // Return value as-is - let SQL Server handle type conversion
        return value;
    }

    private static bool IsDateTimeColumn(string columnName)
    {
        return columnName.Equals("WhenCreated", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("WhenChanged", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("LastLogonTimestamp", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("PasswordLastSet", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("AccountExpires", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("CollectionDateTime", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("StartTime", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("EndTime", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("Timestamp", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("ComputedDate", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("LastResolveAttempt", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("AppliedDate", StringComparison.OrdinalIgnoreCase) ||
               // Certificate validity dates (PKI tables)
               columnName.Equals("CertificateNotBefore", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("CertificateNotAfter", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsBooleanColumn(string columnName)
    {
        return columnName.Equals("Enabled", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("PasswordNeverExpires", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("PasswordExpired", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsTransitive", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsResolved", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsForeignSecurityPrincipal", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsCriticalSystemObject", StringComparison.OrdinalIgnoreCase) ||
               // AD_SiteLink columns
               columnName.Equals("UseNotification", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("TwoWaySync", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("CompressionDisabled", StringComparison.OrdinalIgnoreCase) ||
               // AD_SiteSettings columns
               columnName.Equals("IsAutoTopologyDisabled", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsTopologyCleanupDisabled", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsMinHopsDisabled", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsDetectStaleDisabled", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsInterSiteAutoTopologyDisabled", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsGroupCachingEnabled", StringComparison.OrdinalIgnoreCase) ||
               // AD_DomainController columns
               columnName.Equals("IsGlobalCatalog", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("DisableInboundReplication", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("DisableOutboundReplication", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("DisableNTDSConnTranslation", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("IsRODC", StringComparison.OrdinalIgnoreCase) ||
               // AD_OptionalFeature columns
               columnName.Equals("IsEnabled", StringComparison.OrdinalIgnoreCase) ||
               // AD_Domain domain health columns
               columnName.Equals("DFSRExists", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("FRSExists", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("SYSVOLAccessible", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("DefaultDomainPolicyExists", StringComparison.OrdinalIgnoreCase) ||
               columnName.Equals("DefaultDCPolicyExists", StringComparison.OrdinalIgnoreCase);
    }
}
