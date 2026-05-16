using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CLAWS.Data.Entities;

/// <summary>
/// Represents an API key in the database.
/// </summary>
[Table("ApiKeys", Schema = "app")]
public class ApiKey
{
    /// <summary>
    /// Unique identifier for the API key.
    /// </summary>
    [Key]
    public Guid ApiKeyId { get; set; } = Guid.NewGuid();

    /// <summary>
    /// SHA256 hash of the API key.
    /// </summary>
    [Required]
    [MaxLength(64)]
    public byte[] KeyHash { get; set; } = Array.Empty<byte>();

    /// <summary>
    /// Salt used for hashing.
    /// </summary>
    [Required]
    [MaxLength(32)]
    public byte[] KeySalt { get; set; } = Array.Empty<byte>();

    /// <summary>
    /// First 8 characters of the key for identification.
    /// </summary>
    [Required]
    [MaxLength(8)]
    public string KeyPrefix { get; set; } = string.Empty;

    /// <summary>
    /// Description or name of the API key.
    /// </summary>
    [Required]
    [MaxLength(500)]
    public string Description { get; set; } = string.Empty;

    /// <summary>
    /// User who created the API key.
    /// </summary>
    [Required]
    [MaxLength(256)]
    public string CreatedBy { get; set; } = string.Empty;

    /// <summary>
    /// When the API key was created.
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When the API key was last used.
    /// </summary>
    public DateTime? LastUsedAt { get; set; }

    /// <summary>
    /// When the API key expires.
    /// </summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>
    /// Whether the API key is enabled.
    /// </summary>
    public bool IsEnabled { get; set; } = true;
}
