using CLAWS.Web.Models;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for managing production data in fsapp and ADData schemas.
/// </summary>
public interface IProductionDataService
{
    /// <summary>
    /// Gets all NTFS Permissions collections from fsapp.CollectionInfo.
    /// </summary>
    Task<List<NtfsProductionCollectionItem>> GetNtfsCollectionsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Gets all AD Inventory collections from ADData.CollectionInfo.
    /// </summary>
    Task<List<AdProductionCollectionItem>> GetAdCollectionsAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Deletes an NTFS Permissions collection from fsapp schema by InventoryID.
    /// Uses ON DELETE CASCADE for related tables, with manual cleanup for tables without cascade.
    /// </summary>
    Task<(bool Success, string Message)> DeleteNtfsCollectionAsync(Guid inventoryId, CancellationToken cancellationToken);

    /// <summary>
    /// Deletes an AD Inventory collection from ADData schema by CollectionID.
    /// Uses ON DELETE CASCADE for all related tables.
    /// </summary>
    Task<(bool Success, string Message)> DeleteAdCollectionAsync(Guid collectionId, CancellationToken cancellationToken);

    /// <summary>
    /// Gets the IDs of collections that have active or queued deletion jobs.
    /// </summary>
    List<string> GetActiveDeletionIds();
}
