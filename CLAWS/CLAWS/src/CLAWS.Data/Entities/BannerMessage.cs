using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CLAWS.Data.Entities;

/// <summary>
/// Represents a banner message to be displayed across the application.
/// </summary>
[Table("BannerMessages", Schema = "app")]
public class BannerMessage
{
    /// <summary>
    /// Unique identifier for the banner message.
    /// </summary>
    [Key]
    public Guid BannerMessageId { get; set; }

    /// <summary>
    /// Short title for the banner message.
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    /// <summary>
    /// The message content to display.
    /// </summary>
    [Required]
    [MaxLength(2000)]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Type of message: Info, Warning, or Error.
    /// </summary>
    [Required]
    [MaxLength(20)]
    public string MessageType { get; set; } = BannerMessageTypes.Info;

    /// <summary>
    /// Whether the banner is currently enabled.
    /// </summary>
    public bool IsEnabled { get; set; }

    /// <summary>
    /// Display order (lower values displayed first).
    /// </summary>
    public int DisplayOrder { get; set; }

    /// <summary>
    /// Optional start date for scheduled display.
    /// </summary>
    public DateTime? StartDate { get; set; }

    /// <summary>
    /// Optional end date for scheduled display.
    /// </summary>
    public DateTime? EndDate { get; set; }

    /// <summary>
    /// User who created the banner message.
    /// </summary>
    [Required]
    [MaxLength(256)]
    public string CreatedBy { get; set; } = string.Empty;

    /// <summary>
    /// When the banner message was created.
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// User who last modified the banner message.
    /// </summary>
    [Required]
    [MaxLength(256)]
    public string LastModifiedBy { get; set; } = string.Empty;

    /// <summary>
    /// When the banner message was last modified.
    /// </summary>
    public DateTime LastModifiedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Constants for banner message types.
/// </summary>
public static class BannerMessageTypes
{
    /// <summary>
    /// Informational message (blue).
    /// </summary>
    public const string Info = "Info";

    /// <summary>
    /// Warning message (yellow).
    /// </summary>
    public const string Warning = "Warning";

    /// <summary>
    /// Error/critical message (red).
    /// </summary>
    public const string Error = "Error";

    /// <summary>
    /// All valid message types.
    /// </summary>
    public static readonly string[] All = { Info, Warning, Error };

    /// <summary>
    /// Validates if the given type is valid.
    /// </summary>
    public static bool IsValid(string type) => All.Contains(type);
}
