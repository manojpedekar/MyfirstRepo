namespace CLAWS.Core.Services;

/// <summary>
/// Service for securely retrieving encrypted credentials.
/// </summary>
public interface ISecureCredentialService
{
    /// <summary>
    /// Decrypts the Cloud Integration service account password for use in LDAP connections.
    /// </summary>
    /// <returns>The decrypted password, or null if not configured.</returns>
    string? GetCloudIntegrationPassword();
}
