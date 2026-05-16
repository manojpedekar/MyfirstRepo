using CLAWS.Web.Models;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for retrieving collection logs from EventLog tables.
/// Handles schema selection based on upload merge status.
/// </summary>
public interface ICollectionLogService
{
    /// <summary>
    /// Gets paginated collection logs for all inventories in an upload.
    /// </summary>
    /// <param name="uploadId">Upload ID to get logs for.</param>
    /// <param name="filter">Filter options.</param>
    /// <param name="page">Page number (1-based).</param>
    /// <param name="pageSize">Number of items per page.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Paginated collection logs.</returns>
    Task<PagedCollectionLogs> GetLogsForUploadAsync(
        Guid uploadId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets paginated collection logs for a specific inventory.
    /// </summary>
    /// <param name="uploadId">Upload ID the inventory belongs to.</param>
    /// <param name="inventoryId">Inventory ID to get logs for.</param>
    /// <param name="filter">Filter options.</param>
    /// <param name="page">Page number (1-based).</param>
    /// <param name="pageSize">Number of items per page.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Paginated collection logs.</returns>
    Task<PagedCollectionLogs> GetLogsForInventoryAsync(
        Guid uploadId,
        Guid inventoryId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a summary of log counts by severity for an upload.
    /// </summary>
    /// <param name="uploadId">Upload ID to get summary for.</param>
    /// <param name="inventoryId">Optional inventory ID to filter by.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Dictionary of severity -> count.</returns>
    Task<Dictionary<string, int>> GetLogSummaryAsync(
        Guid uploadId,
        Guid? inventoryId = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets paginated collection logs for an ADInventory domain (by CollectionID).
    /// </summary>
    /// <param name="uploadId">Upload ID the domain belongs to.</param>
    /// <param name="collectionId">CollectionID to get logs for.</param>
    /// <param name="filter">Filter options.</param>
    /// <param name="page">Page number (1-based).</param>
    /// <param name="pageSize">Number of items per page.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Paginated collection logs.</returns>
    Task<PagedCollectionLogs> GetLogsForADDomainAsync(
        Guid uploadId,
        Guid collectionId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a summary of log counts by severity for an ADInventory domain.
    /// </summary>
    /// <param name="uploadId">Upload ID to get summary for.</param>
    /// <param name="collectionId">CollectionID to filter by.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Dictionary of severity -> count.</returns>
    Task<Dictionary<string, int>> GetLogSummaryForADDomainAsync(
        Guid uploadId,
        Guid collectionId,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets paginated collection logs for all ADInventory domains in an upload.
    /// </summary>
    /// <param name="uploadId">Upload ID to get logs for.</param>
    /// <param name="filter">Filter options.</param>
    /// <param name="page">Page number (1-based).</param>
    /// <param name="pageSize">Number of items per page.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Paginated collection logs.</returns>
    Task<PagedCollectionLogs> GetLogsForAllADDomainsAsync(
        Guid uploadId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets paginated collection logs for an NTFS Permissions collection from production schema.
    /// </summary>
    /// <param name="inventoryId">Inventory ID to get logs for.</param>
    /// <param name="filter">Filter options.</param>
    /// <param name="page">Page number (1-based).</param>
    /// <param name="pageSize">Number of items per page.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Paginated collection logs.</returns>
    Task<PagedCollectionLogs> GetLogsForProductionNtfsAsync(
        Guid inventoryId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets paginated collection logs for an AD Inventory collection from production schema.
    /// </summary>
    /// <param name="collectionId">Collection ID to get logs for.</param>
    /// <param name="filter">Filter options.</param>
    /// <param name="page">Page number (1-based).</param>
    /// <param name="pageSize">Number of items per page.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Paginated collection logs.</returns>
    Task<PagedCollectionLogs> GetLogsForProductionAdAsync(
        Guid collectionId,
        CollectionLogFilter? filter = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken cancellationToken = default);
}
