namespace CLAWS.Core.Models;

/// <summary>
/// Represents the current status of an upload.
/// </summary>
public enum UploadStatus
{
    /// <summary>File is being uploaded to the server.</summary>
    Uploading,

    /// <summary>Upload completed, validating ZIP structure.</summary>
    ValidatingZip,

    /// <summary>Validating SQLite database structure and versions.</summary>
    ValidatingDatabase,

    /// <summary>Validation passed, import is queued.</summary>
    Queued,

    /// <summary>Import is in progress.</summary>
    Importing,

    /// <summary>Import completed successfully.</summary>
    Completed,

    /// <summary>Upload or import failed.</summary>
    Failed,

    /// <summary>Upload was cancelled.</summary>
    Cancelled
}
