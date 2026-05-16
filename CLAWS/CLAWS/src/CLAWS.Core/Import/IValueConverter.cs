using System.Runtime.Versioning;
using CLAWS.Core.Models;

namespace CLAWS.Core.Import;

/// <summary>
/// Column information for value conversion.
/// </summary>
public class ColumnInfo
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public bool IsNullable { get; set; }
    public bool IsPrimaryKey { get; set; }
}

/// <summary>
/// Converts SQLite values to SQL Server compatible values.
/// </summary>
public interface IValueConverter
{
    /// <summary>
    /// Converts a value from SQLite to SQL Server format.
    /// </summary>
    /// <param name="value">The value to convert.</param>
    /// <param name="column">Column metadata.</param>
    /// <returns>The converted value.</returns>
    object? Convert(object? value, ColumnInfo column);
}

/// <summary>
/// Factory for creating type-specific value converters.
/// </summary>
public interface IValueConverterFactory
{
    /// <summary>
    /// Creates a value converter for the specified upload type.
    /// </summary>
    /// <param name="uploadType">The type of upload.</param>
    /// <returns>A value converter instance.</returns>
    IValueConverter CreateConverter(UploadType uploadType);
}

/// <summary>
/// Implementation of value converter factory.
/// </summary>
[SupportedOSPlatform("windows")]
public class ValueConverterFactory : IValueConverterFactory
{
    /// <inheritdoc/>
    public IValueConverter CreateConverter(UploadType uploadType) => uploadType switch
    {
        UploadType.NTFSPermissions => new NtfsPermissionsValueConverter(),
        UploadType.ADInventory => new AdInventoryValueConverter(),
        _ => new DefaultValueConverter()
    };
}

/// <summary>
/// Default value converter with basic type conversion.
/// </summary>
public class DefaultValueConverter : IValueConverter
{
    /// <inheritdoc/>
    public virtual object? Convert(object? value, ColumnInfo column)
    {
        if (value == null || value == DBNull.Value)
            return null;

        // Handle empty strings for specific column types
        if (value is string strValue && string.IsNullOrWhiteSpace(strValue))
        {
            // Empty strings for GUID columns should be null
            if (column.Name.EndsWith("_GUID", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("InventoryID", StringComparison.OrdinalIgnoreCase) ||
                column.Name.Equals("ObjectGUID", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            // Empty strings for DateTime columns should be null
            if (column.Name.EndsWith("Date", StringComparison.OrdinalIgnoreCase) ||
                column.Name.EndsWith("DateTime", StringComparison.OrdinalIgnoreCase) ||
                column.Name.EndsWith("Time", StringComparison.OrdinalIgnoreCase) ||
                column.Name.EndsWith("At", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }
        }

        // Convert InventoryID to GUID
        if (column.Name.Equals("InventoryID", StringComparison.OrdinalIgnoreCase))
        {
            if (value is string strVal && Guid.TryParse(strVal, out var guid))
            {
                return guid;
            }
        }

        return value;
    }
}
