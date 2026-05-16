using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CLAWS.Core.Configuration;
using CLAWS.Core.Services;
using CLAWS.Data.Entities;
using CLAWS.Web.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Controllers;

/// <summary>
/// Controller for user authentication.
/// </summary>
public class AccountController : Controller
{
    private readonly ILogger<AccountController> _logger;
    private readonly ILdapAuthenticationService _ldapService;
    private readonly IAppLogService _appLogService;
    private readonly IApiKeyService _apiKeyService;
    private readonly LdapSettings _ldapSettings;
    private readonly AppSettings _appSettings;

    public AccountController(
        ILogger<AccountController> logger,
        ILdapAuthenticationService ldapService,
        IAppLogService appLogService,
        IApiKeyService apiKeyService,
        LdapSettings ldapSettings,
        AppSettings appSettings)
    {
        _logger = logger;
        _ldapService = ldapService;
        _appLogService = appLogService;
        _apiKeyService = apiKeyService;
        _ldapSettings = ldapSettings;
        _appSettings = appSettings;
    }

    [AllowAnonymous]
    [HttpGet]
    public IActionResult Login(string? returnUrl = null)
    {
        // If user is already authenticated, redirect to home
        if (User.Identity?.IsAuthenticated == true)
        {
            return RedirectToLocal(returnUrl);
        }

        var model = new LoginViewModel
        {
            ReturnUrl = returnUrl,
            IsLdapConfigured = _ldapSettings.IsConfigured,
            AllowKeymasterFallback = _ldapSettings.AllowKeymasterFallback,
            Domain = _ldapSettings.Domain,
            KeymasterUsername = _ldapSettings.KeymasterUsername,
            Port = _ldapSettings.Port
        };

        return View(model);
    }

    [AllowAnonymous]
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Login(LoginViewModel model)
    {
        model.IsLdapConfigured = _ldapSettings.IsConfigured;
        model.AllowKeymasterFallback = _ldapSettings.AllowKeymasterFallback;
        model.Domain = _ldapSettings.Domain;
        model.KeymasterUsername = _ldapSettings.KeymasterUsername;
        model.Port = _ldapSettings.Port;

        // If UseKeymaster is checked, override username with Keymaster account
        if (model.UseKeymaster && _ldapSettings.AllowKeymasterFallback)
        {
            model.Username = _ldapSettings.KeymasterUsername;
        }

        if (string.IsNullOrWhiteSpace(model.Username))
        {
            model.ErrorMessage = "Username is required.";
            return View(model);
        }

        if (string.IsNullOrWhiteSpace(model.Password))
        {
            model.ErrorMessage = "Password is required.";
            return View(model);
        }

        var result = await _ldapService.AuthenticateAsync(model.Username, model.Password);

        if (!result.Success)
        {
            _logger.LogWarning("Failed login attempt for user {Username} from {IP}",
                model.Username, HttpContext.Connection.RemoteIpAddress);

            await _appLogService.LogSecurityEventAsync(
                $"Failed login attempt for user {model.Username}",
                model.Username,
                HttpContext.Connection.RemoteIpAddress?.ToString(),
                CancellationToken.None);

            model.ErrorMessage = result.ErrorMessage ?? "Invalid username or password.";
            return View(model);
        }

        // Create claims for the authenticated user
        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.Name, result.Username ?? model.Username),
            new Claim(ClaimTypes.NameIdentifier, result.Username ?? model.Username),
            new Claim("AuthenticationType", result.AuthType.ToString())
        };

        if (!string.IsNullOrEmpty(result.DisplayName))
        {
            claims.Add(new Claim("DisplayName", result.DisplayName));
        }

        if (!string.IsNullOrEmpty(result.Email))
        {
            claims.Add(new Claim(ClaimTypes.Email, result.Email));
        }

        // Add group claims - only include groups that match configured authorization roles
        // This prevents cookie size issues when users have many group memberships
        var relevantGroups = GetRelevantGroups(result.Groups);
        foreach (var group in relevantGroups)
        {
            claims.Add(new Claim(ClaimTypes.Role, group));
        }

        // Extended logging for group details (when enabled)
        if (_appSettings.Logging.EnableExtendedLogging)
        {
            _logger.LogInformation("User {Username} has {TotalGroups} total groups, {RelevantGroups} relevant for authorization: [{Groups}]",
                result.Username, result.Groups.Count, relevantGroups.Count,
                relevantGroups.Count > 0 ? string.Join(", ", relevantGroups) : "(none)");
        }

        var claimsIdentity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);

        var authProperties = new AuthenticationProperties
        {
            IsPersistent = model.RememberMe,
            ExpiresUtc = model.RememberMe
                ? DateTimeOffset.UtcNow.AddDays(30)
                : DateTimeOffset.UtcNow.AddHours(8)
        };

        await HttpContext.SignInAsync(
            CookieAuthenticationDefaults.AuthenticationScheme,
            new ClaimsPrincipal(claimsIdentity),
            authProperties);

        _logger.LogInformation("User {Username} logged in successfully via {AuthType}",
            result.Username, result.AuthType);

        // Extended logging for groups and role matching (when enabled)
        if (_appSettings.Logging.EnableExtendedLogging)
        {
            // Log user's groups for debugging authorization
            _logger.LogInformation("User {Username} has {GroupCount} groups: [{Groups}]",
                result.Username,
                result.Groups.Count,
                string.Join(", ", result.Groups));

            // Determine and log matched roles based on authorization settings
            var matchedRoles = DetermineUserRoles(result.Groups, result.AuthType.ToString());
            _logger.LogInformation("User {Username} matched roles: [{Roles}]",
                result.Username,
                matchedRoles.Count > 0 ? string.Join(", ", matchedRoles) : "(none - using default access)");

            // Log authorization configuration for comparison
            if (_appSettings.Authorization.IsConfigured)
            {
                _logger.LogInformation("Authorization config - SiteAdmin: {SiteAdmin}, NtfsPermsAdmin: {NtfsPermsAdmin}, AdAdmin: {AdAdmin}",
                    _appSettings.Authorization.SiteAdminGroup ?? "(not set)",
                    _appSettings.Authorization.NtfsPermsAdminGroup ?? "(not set)",
                    _appSettings.Authorization.AdAdminGroup ?? "(not set)");
            }
        }

        if (!_appSettings.Authorization.IsConfigured)
        {
            _logger.LogWarning("Authorization not configured - user {Username} will have default access (all features visible)",
                result.Username);
        }

        await _appLogService.LogSecurityEventAsync(
            $"User {result.Username} logged in via {result.AuthType}",
            result.Username,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            CancellationToken.None);

        return RedirectToLocal(model.ReturnUrl);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Logout()
    {
        var username = User.Identity?.Name;

        await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);

        _logger.LogInformation("User {Username} logged out", username);

        await _appLogService.LogSecurityEventAsync(
            $"User {username} logged out",
            username,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            CancellationToken.None);

        return RedirectToAction("Index", "Home");
    }

    [AllowAnonymous]
    public IActionResult AccessDenied(string? returnUrl = null)
    {
        ViewData["ReturnUrl"] = returnUrl;
        return View();
    }

    /// <summary>
    /// Personal API key management page.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> MyApiKeys(CancellationToken cancellationToken)
    {
        var username = User.Identity?.Name ?? "";
        var keys = await _apiKeyService.GetKeysByUserAsync(username, cancellationToken);
        return View(keys);
    }

    /// <summary>
    /// Generate a new personal API key.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> GenerateApiKey(string description, DateTime? expiresAt, CancellationToken cancellationToken)
    {
        var username = User.Identity?.Name ?? "Unknown";
        var (_, plainTextKey) = await _apiKeyService.GenerateKeyAsync(description, username, expiresAt, cancellationToken);

        TempData["NewApiKey"] = plainTextKey;
        TempData["NewApiKeyDescription"] = description;

        return RedirectToAction(nameof(MyApiKeys));
    }

    /// <summary>
    /// Revoke a personal API key.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> RevokeApiKey(Guid id, CancellationToken cancellationToken)
    {
        var username = User.Identity?.Name ?? "";

        // Verify the key belongs to the current user
        var key = await _apiKeyService.GetKeyByIdAsync(id, cancellationToken);
        if (key == null || key.CreatedBy != username)
        {
            TempData["Error"] = "API key not found or you don't have permission to revoke it.";
            return RedirectToAction(nameof(MyApiKeys));
        }

        await _apiKeyService.RevokeKeyAsync(id, cancellationToken);
        TempData["Success"] = "API key revoked successfully.";
        return RedirectToAction(nameof(MyApiKeys));
    }

    /// <summary>
    /// Delete a personal API key.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteApiKey(Guid id, CancellationToken cancellationToken)
    {
        var username = User.Identity?.Name ?? "";

        // Verify the key belongs to the current user
        var key = await _apiKeyService.GetKeyByIdAsync(id, cancellationToken);
        if (key == null || key.CreatedBy != username)
        {
            TempData["Error"] = "API key not found or you don't have permission to delete it.";
            return RedirectToAction(nameof(MyApiKeys));
        }

        await _apiKeyService.DeleteKeyAsync(id, cancellationToken);
        TempData["Success"] = "API key deleted successfully.";
        return RedirectToAction(nameof(MyApiKeys));
    }

    private IActionResult RedirectToLocal(string? returnUrl)
    {
        if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
        {
            return Redirect(returnUrl);
        }

        return RedirectToAction("Index", "Home");
    }

    /// <summary>
    /// Filters user groups to only include those that match configured authorization roles.
    /// This prevents cookie size issues when users have many group memberships.
    /// </summary>
    private List<string> GetRelevantGroups(List<string> userGroups)
    {
        var relevantGroups = new List<string>();
        var auth = _appSettings.Authorization;

        // Collect all configured group names
        var configuredGroups = new List<string?>
        {
            auth.SiteAdminGroup,
            auth.NtfsPermsAdminGroup,
            auth.AdAdminGroup
        };

        // Only include user groups that match a configured authorization group
        foreach (var userGroup in userGroups)
        {
            if (configuredGroups.Any(cg =>
                !string.IsNullOrEmpty(cg) &&
                cg.Equals(userGroup, StringComparison.OrdinalIgnoreCase)))
            {
                relevantGroups.Add(userGroup);
            }
        }

        return relevantGroups;
    }

    /// <summary>
    /// Determines which application roles the user matches based on their groups.
    /// </summary>
    private List<string> DetermineUserRoles(List<string> userGroups, string authType)
    {
        var matchedRoles = new List<string>();

        // Keymaster always gets admin
        if (authType == "Keymaster")
        {
            matchedRoles.Add("Site Administrator (Keymaster)");
            return matchedRoles;
        }

        // Check each configured role group
        var auth = _appSettings.Authorization;

        if (!string.IsNullOrEmpty(auth.SiteAdminGroup) &&
            userGroups.Any(g => g.Equals(auth.SiteAdminGroup, StringComparison.OrdinalIgnoreCase)))
        {
            matchedRoles.Add($"Site Administrator (matched: {auth.SiteAdminGroup})");
        }

        if (!string.IsNullOrEmpty(auth.NtfsPermsAdminGroup) &&
            userGroups.Any(g => g.Equals(auth.NtfsPermsAdminGroup, StringComparison.OrdinalIgnoreCase)))
        {
            matchedRoles.Add($"NTFS Perms Admin (matched: {auth.NtfsPermsAdminGroup})");
        }

        if (!string.IsNullOrEmpty(auth.AdAdminGroup) &&
            userGroups.Any(g => g.Equals(auth.AdAdminGroup, StringComparison.OrdinalIgnoreCase)))
        {
            matchedRoles.Add($"AD Admin (matched: {auth.AdAdminGroup})");
        }

        return matchedRoles;
    }
}
