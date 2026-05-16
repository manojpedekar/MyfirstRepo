using CLAWS.Core.Services;

namespace CLAWS.Web.Services;

/// <summary>
/// Service for securely retrieving encrypted credentials.
/// </summary>
public class SecureCredentialService : ISecureCredentialService
{
    private readonly IConfigurationFileService _configFileService;

    public SecureCredentialService(IConfigurationFileService configFileService)
    {
        _configFileService = configFileService;
    }

    /// <inheritdoc/>
    public string? GetCloudIntegrationPassword()
    {
        return _configFileService.DecryptCloudIntegrationPassword();
    }
}
