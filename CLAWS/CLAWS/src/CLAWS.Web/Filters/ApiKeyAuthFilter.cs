using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using CLAWS.Core.Models;
using CLAWS.Web.Services;

namespace CLAWS.Web.Filters;

/// <summary>
/// Filter for API key authentication.
/// </summary>
public class ApiKeyAuthFilter : IAsyncActionFilter
{
    private const string ApiKeyHeaderName = "X-API-Key";
    private readonly IApiKeyService _apiKeyService;
    private readonly ILogger<ApiKeyAuthFilter> _logger;

    public ApiKeyAuthFilter(IApiKeyService apiKeyService, ILogger<ApiKeyAuthFilter> logger)
    {
        _apiKeyService = apiKeyService;
        _logger = logger;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        // Skip authentication for endpoints with AllowAnonymous
        var endpoint = context.HttpContext.GetEndpoint();
        if (endpoint?.Metadata.GetMetadata<Microsoft.AspNetCore.Authorization.AllowAnonymousAttribute>() != null)
        {
            await next();
            return;
        }

        // Check for API key header
        if (!context.HttpContext.Request.Headers.TryGetValue(ApiKeyHeaderName, out var potentialApiKey))
        {
            _logger.LogWarning("API request without API key from {IP}",
                context.HttpContext.Connection.RemoteIpAddress);

            context.Result = new UnauthorizedObjectResult(
                ApiResponse.Fail("UNAUTHORIZED", "API key required. Provide X-API-Key header."));
            return;
        }

        var apiKey = potentialApiKey.ToString();
        var validatedKey = await _apiKeyService.ValidateKeyAsync(apiKey);

        if (validatedKey == null)
        {
            _logger.LogWarning("Invalid API key attempt from {IP}: {KeyPrefix}...",
                context.HttpContext.Connection.RemoteIpAddress,
                apiKey.Length >= 8 ? apiKey[..8] : apiKey);

            context.Result = new UnauthorizedObjectResult(
                ApiResponse.Fail("UNAUTHORIZED", "Invalid or expired API key."));
            return;
        }

        // Store the API key info in HttpContext for later use
        context.HttpContext.Items["ApiKeyId"] = validatedKey.ApiKeyId;
        context.HttpContext.Items["ApiKeyUser"] = $"API:{validatedKey.Description}";
        context.HttpContext.Items["ApiKeyCreatedBy"] = validatedKey.CreatedBy;

        _logger.LogDebug("API key authenticated: {Prefix}... created by {CreatedBy}",
            validatedKey.KeyPrefix, validatedKey.CreatedBy);

        await next();
    }
}
