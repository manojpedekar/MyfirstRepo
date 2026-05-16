using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using CLAWS.Web.Models;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Home controller for the main pages.
/// </summary>
public class HomeController : Controller
{
    private readonly ILogger<HomeController> _logger;
    private readonly AppSettings _appSettings;
    private readonly IDiskSpaceService _diskSpaceService;
    private readonly IWebHostEnvironment _webHostEnvironment;

    /// <summary>
    /// Name of the CollectNTFSPerms download bundle file.
    /// </summary>
    public const string CollectNTFSPermsZipFileName = "CollectNTFSPerms.zip";

    /// <summary>
    /// Name of the CollectNTFSPerms metadata file.
    /// </summary>
    public const string CollectNTFSPermsMetadataFileName = "collectntfsperms.json";

    /// <summary>
    /// Name of the ADInventory download bundle file.
    /// </summary>
    public const string ADInventoryZipFileName = "ADInventory.zip";

    /// <summary>
    /// Name of the ADInventory metadata file.
    /// </summary>
    public const string ADInventoryMetadataFileName = "adinventory.json";

    public HomeController(
        ILogger<HomeController> logger,
        AppSettings appSettings,
        IDiskSpaceService diskSpaceService,
        IWebHostEnvironment webHostEnvironment)
    {
        _logger = logger;
        _appSettings = appSettings;
        _diskSpaceService = diskSpaceService;
        _webHostEnvironment = webHostEnvironment;
    }

    public IActionResult Index()
    {
        var model = new HomeViewModel
        {
            IsDbConfigured = _appSettings.SqlServer.IsConfigured,
            IsAuthConfigured = _appSettings.Authorization.IsConfigured,
            IsUsingAppDirectory = _appSettings.Storage.IsUsingApplicationDirectory(
                Path.GetDirectoryName(typeof(Program).Assembly.Location) ?? ""),
            IsDownloadAvailable = IsCollectNTFSPermsDownloadAvailable(),
            DownloadMetadata = GetCollectNTFSPermsMetadata(),
            IsADInventoryDownloadAvailable = IsADInventoryDownloadAvailable(),
            ADInventoryMetadata = GetADInventoryMetadata()
        };

        return View(model);
    }

    /// <summary>
    /// Checks if the CollectNTFSPerms download bundle is available.
    /// </summary>
    private bool IsCollectNTFSPermsDownloadAvailable()
    {
        var downloadPath = Path.Combine(_webHostEnvironment.WebRootPath ?? "", "downloads", CollectNTFSPermsZipFileName);
        return System.IO.File.Exists(downloadPath);
    }

    /// <summary>
    /// Gets the CollectNTFSPerms metadata from the JSON file.
    /// </summary>
    private CollectNTFSPermsMetadata? GetCollectNTFSPermsMetadata()
    {
        var metadataPath = Path.Combine(_webHostEnvironment.WebRootPath ?? "", "downloads", CollectNTFSPermsMetadataFileName);
        if (!System.IO.File.Exists(metadataPath))
        {
            return null;
        }

        try
        {
            var json = System.IO.File.ReadAllText(metadataPath);
            return JsonSerializer.Deserialize<CollectNTFSPermsMetadata>(json);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to read CollectNTFSPerms metadata from {Path}", metadataPath);
            return null;
        }
    }

    /// <summary>
    /// Checks if the ADInventory download bundle is available.
    /// </summary>
    private bool IsADInventoryDownloadAvailable()
    {
        var downloadPath = Path.Combine(_webHostEnvironment.WebRootPath ?? "", "downloads", ADInventoryZipFileName);
        return System.IO.File.Exists(downloadPath);
    }

    /// <summary>
    /// Gets the ADInventory metadata from the JSON file.
    /// </summary>
    private ADInventoryMetadata? GetADInventoryMetadata()
    {
        var metadataPath = Path.Combine(_webHostEnvironment.WebRootPath ?? "", "downloads", ADInventoryMetadataFileName);
        if (!System.IO.File.Exists(metadataPath))
        {
            return null;
        }

        try
        {
            var json = System.IO.File.ReadAllText(metadataPath);
            return JsonSerializer.Deserialize<ADInventoryMetadata>(json);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to read ADInventory metadata from {Path}", metadataPath);
            return null;
        }
    }

    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = HttpContext.TraceIdentifier });
    }
}
