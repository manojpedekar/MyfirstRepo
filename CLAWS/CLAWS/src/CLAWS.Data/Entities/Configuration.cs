using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CLAWS.Data.Entities;

/// <summary>
/// Represents a configuration setting in the database.
/// </summary>
[Table("Configuration", Schema = "app")]
public class ConfigurationEntry
{
    /// <summary>
    /// Configuration key.
    /// </summary>
    [Key]
    [MaxLength(100)]
    public string ConfigKey { get; set; } = string.Empty;

    /// <summary>
    /// Configuration value.
    /// </summary>
    public string? ConfigValue { get; set; }

    /// <summary>
    /// Whether the value is encrypted.
    /// </summary>
    public bool IsEncrypted { get; set; }

    /// <summary>
    /// User who last modified the configuration.
    /// </summary>
    [Required]
    [MaxLength(256)]
    public string LastModifiedBy { get; set; } = string.Empty;

    /// <summary>
    /// When the configuration was last modified.
    /// </summary>
    public DateTime LastModifiedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Description of the configuration setting.
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }
}
