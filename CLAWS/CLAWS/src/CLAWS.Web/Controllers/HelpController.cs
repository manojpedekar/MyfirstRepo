using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Markdig;
using System.Text.Json;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for serving help documentation from markdown files.
/// </summary>
[AllowAnonymous]
public class HelpController : Controller
{
    private readonly IWebHostEnvironment _env;
    private readonly ILogger<HelpController> _logger;
    private readonly string? _helpBasePath;
    private readonly MarkdownPipeline _markdownPipeline;

    public HelpController(IWebHostEnvironment env, ILogger<HelpController> logger, IConfiguration configuration)
    {
        _env = env;
        _logger = logger;

        // Try multiple locations for help files:
        // 1. Configured path in appsettings (HelpDocsPath)
        // 2. docs/help in content root (deployed with app)
        // 3. Solution root docs/help (development)
        var configuredPath = configuration["HelpDocsPath"];
        var possiblePaths = new List<string>();

        if (!string.IsNullOrEmpty(configuredPath))
        {
            possiblePaths.Add(configuredPath);
        }

        // Check if deployed with app
        possiblePaths.Add(Path.Combine(_env.ContentRootPath, "docs", "help"));

        // Development: go up from web project to solution root
        var solutionRoot = Path.GetFullPath(Path.Combine(_env.ContentRootPath, "..", "..", ".."));
        possiblePaths.Add(Path.Combine(solutionRoot, "docs", "help"));

        // Find first path that contains _metadata.json
        foreach (var path in possiblePaths)
        {
            var metadataPath = Path.Combine(path, "_metadata.json");
            if (System.IO.File.Exists(metadataPath))
            {
                _helpBasePath = path;
                _logger.LogInformation("Help documentation found at: {Path}", path);
                break;
            }
        }

        if (_helpBasePath == null)
        {
            _logger.LogWarning("Help documentation not found. Searched: {Paths}", string.Join(", ", possiblePaths));
        }

        // Configure Markdig pipeline with common extensions
        _markdownPipeline = new MarkdownPipelineBuilder()
            .UseAdvancedExtensions()
            .UseAutoLinks()
            .Build();
    }

    /// <summary>
    /// Help index page showing all sections and popular articles.
    /// </summary>
    [HttpGet]
    public IActionResult Index()
    {
        var metadata = GetMetadata();
        if (metadata == null)
        {
            return HelpNotAvailable();
        }

        var model = new HelpIndexViewModel
        {
            Title = metadata.Title,
            Description = metadata.Description,
            Sections = metadata.Sections,
            PopularArticles = ResolvePopularArticles(metadata),
            ContactEmail = metadata.ContactEmail
        };

        return View(model);
    }

    /// <summary>
    /// Display a specific article from a section.
    /// </summary>
    [HttpGet("Help/{category}/{article}")]
    public IActionResult Article(string category, string article)
    {
        var metadata = GetMetadata();
        if (metadata == null || _helpBasePath == null)
        {
            return HelpNotAvailable();
        }

        // Strip .md extension if present (markdown links include the extension)
        var articleId = article.EndsWith(".md", StringComparison.OrdinalIgnoreCase)
            ? article[..^3]
            : article;

        // Find the section
        var sectionInfo = metadata.Sections.FirstOrDefault(s =>
            s.Id.Equals(category, StringComparison.OrdinalIgnoreCase));

        if (sectionInfo == null)
        {
            return NotFound($"Section '{category}' not found.");
        }

        // Find the article
        var articleInfo = sectionInfo.Articles.FirstOrDefault(a =>
            a.Id.Equals(articleId, StringComparison.OrdinalIgnoreCase));

        if (articleInfo == null)
        {
            return NotFound($"Article '{articleId}' not found in section '{category}'.");
        }

        // Read and render the markdown file
        var filePath = Path.Combine(_helpBasePath, articleInfo.File);
        if (!System.IO.File.Exists(filePath))
        {
            _logger.LogWarning("Help file not found: {FilePath}", filePath);
            return NotFound($"Help file not found.");
        }

        var markdown = System.IO.File.ReadAllText(filePath);
        var htmlContent = Markdown.ToHtml(markdown, _markdownPipeline);

        var model = new HelpArticleViewModel
        {
            Title = articleInfo.Title,
            SectionId = sectionInfo.Id,
            SectionTitle = sectionInfo.Title,
            SectionIcon = sectionInfo.Icon,
            HtmlContent = htmlContent,
            AllSections = metadata.Sections,
            CurrentArticle = articleInfo
        };

        return View(model);
    }

    /// <summary>
    /// Display footer link pages (FAQ, Release Notes, Contact).
    /// </summary>
    [HttpGet("Help/{page}")]
    public IActionResult Page(string page)
    {
        var metadata = GetMetadata();
        if (metadata == null || _helpBasePath == null)
        {
            return HelpNotAvailable();
        }

        // Strip .md extension if present (markdown links include the extension)
        var pageId = page.EndsWith(".md", StringComparison.OrdinalIgnoreCase)
            ? page[..^3]
            : page;

        // Check footer links
        var footerLink = metadata.FooterLinks?.FirstOrDefault(f =>
            f.File.StartsWith(pageId, StringComparison.OrdinalIgnoreCase));

        string? filePath = null;
        string? title = null;

        if (footerLink != null)
        {
            filePath = Path.Combine(_helpBasePath, footerLink.File);
            title = footerLink.Title;
        }
        else
        {
            // Try direct file match
            var possibleFile = Path.Combine(_helpBasePath, $"{pageId}.md");
            if (System.IO.File.Exists(possibleFile))
            {
                filePath = possibleFile;
                title = pageId;
            }
        }

        if (filePath == null || !System.IO.File.Exists(filePath))
        {
            return NotFound($"Page '{page}' not found.");
        }

        var markdown = System.IO.File.ReadAllText(filePath);
        var htmlContent = Markdown.ToHtml(markdown, _markdownPipeline);

        var model = new HelpArticleViewModel
        {
            Title = title ?? page,
            HtmlContent = htmlContent,
            AllSections = metadata.Sections
        };

        return View("Article", model);
    }

    private HelpMetadata? GetMetadata()
    {
        if (_helpBasePath == null)
        {
            return null;
        }

        var metadataPath = Path.Combine(_helpBasePath, "_metadata.json");
        if (!System.IO.File.Exists(metadataPath))
        {
            _logger.LogWarning("Help metadata file not found: {Path}", metadataPath);
            return null;
        }

        try
        {
            var json = System.IO.File.ReadAllText(metadataPath);
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            };
            return JsonSerializer.Deserialize<HelpMetadata>(json, options);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse help metadata");
            return null;
        }
    }

    /// <summary>
    /// Returns a content result when help is not available instead of trying to render a view.
    /// </summary>
    private IActionResult HelpNotAvailable()
    {
        return Content(@"<!DOCTYPE html>
<html>
<head>
    <title>Help - Not Available</title>
    <link rel=""stylesheet"" href=""https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css"" />
    <link rel=""stylesheet"" href=""https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css"" />
</head>
<body>
    <div class=""container py-5"">
        <div class=""text-center"">
            <i class=""bi bi-question-circle text-muted"" style=""font-size: 4rem;""></i>
            <h1 class=""mt-3"">Help Documentation Not Available</h1>
            <p class=""text-muted"">The help documentation has not been deployed to this server.</p>
            <p class=""text-muted small"">
                To enable help, deploy the <code>docs/help</code> folder to the application directory,
                or configure the <code>HelpDocsPath</code> setting in appsettings.json.
            </p>
            <a href=""/"" class=""btn btn-primary mt-3"">
                <i class=""bi bi-house""></i> Return to Home
            </a>
        </div>
    </div>
</body>
</html>", "text/html");
    }

    private List<PopularArticleInfo> ResolvePopularArticles(HelpMetadata metadata)
    {
        var result = new List<PopularArticleInfo>();

        if (metadata.PopularArticles == null) return result;

        foreach (var articlePath in metadata.PopularArticles)
        {
            var parts = articlePath.Split('/');
            if (parts.Length != 2) continue;

            var sectionId = parts[0];
            var articleId = parts[1];

            var section = metadata.Sections.FirstOrDefault(s => s.Id == sectionId);
            var article = section?.Articles.FirstOrDefault(a => a.Id == articleId);

            if (section != null && article != null)
            {
                result.Add(new PopularArticleInfo
                {
                    SectionId = sectionId,
                    SectionTitle = section.Title,
                    SectionIcon = section.Icon,
                    ArticleId = articleId,
                    ArticleTitle = article.Title
                });
            }
        }

        return result;
    }
}

#region ViewModels

public class HelpIndexViewModel
{
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public List<HelpSection> Sections { get; set; } = new();
    public List<PopularArticleInfo> PopularArticles { get; set; } = new();
    public string? ContactEmail { get; set; }
}

public class HelpArticleViewModel
{
    public string Title { get; set; } = string.Empty;
    public string? SectionId { get; set; }
    public string? SectionTitle { get; set; }
    public string? SectionIcon { get; set; }
    public string HtmlContent { get; set; } = string.Empty;
    public List<HelpSection> AllSections { get; set; } = new();
    public HelpArticle? CurrentArticle { get; set; }
}

public class PopularArticleInfo
{
    public string SectionId { get; set; } = string.Empty;
    public string SectionTitle { get; set; } = string.Empty;
    public string? SectionIcon { get; set; }
    public string ArticleId { get; set; } = string.Empty;
    public string ArticleTitle { get; set; } = string.Empty;
}

#endregion

#region Metadata Models

public class HelpMetadata
{
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string? ContentOwner { get; set; }
    public string? ContactEmail { get; set; }
    public List<HelpSection> Sections { get; set; } = new();
    public List<string>? PopularArticles { get; set; }
    public List<FooterLink>? FooterLinks { get; set; }
}

public class HelpSection
{
    public string Id { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Icon { get; set; }
    public string? Description { get; set; }
    public List<HelpArticle> Articles { get; set; } = new();
}

public class HelpArticle
{
    public string Id { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string File { get; set; } = string.Empty;
}

public class FooterLink
{
    public string Title { get; set; } = string.Empty;
    public string File { get; set; } = string.Empty;
}

#endregion
