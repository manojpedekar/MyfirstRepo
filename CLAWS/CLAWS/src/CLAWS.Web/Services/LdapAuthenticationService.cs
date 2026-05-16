using System.DirectoryServices.Protocols;
using System.Net;
using System.Security;
using CLAWS.Core.Configuration;

namespace CLAWS.Web.Services;

/// <summary>
/// Result of an authentication attempt.
/// </summary>
public class AuthenticationResult
{
    public bool Success { get; set; }
    public string? Username { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public string? ErrorMessage { get; set; }
    public AuthenticationType AuthType { get; set; }
    public List<string> Groups { get; set; } = new();
}

/// <summary>
/// Type of authentication used.
/// </summary>
public enum AuthenticationType
{
    Ldap,
    Keymaster
}

/// <summary>
/// Service for LDAP authentication.
/// </summary>
public interface ILdapAuthenticationService
{
    /// <summary>
    /// Authenticates a user against LDAP or Keymaster fallback.
    /// </summary>
    Task<AuthenticationResult> AuthenticateAsync(string username, string password);

    /// <summary>
    /// Tests the LDAP connection with the current configuration.
    /// </summary>
    Task<(bool Success, string Message)> TestConnectionAsync();

    /// <summary>
    /// Checks if LDAP authentication is enabled.
    /// </summary>
    bool IsLdapEnabled { get; }

    /// <summary>
    /// Checks if Keymaster fallback is allowed.
    /// </summary>
    bool IsKeymasterFallbackAllowed { get; }
}

/// <summary>
/// Implementation of LDAP authentication service.
/// </summary>
public class LdapAuthenticationService : ILdapAuthenticationService
{
    private readonly ILogger<LdapAuthenticationService> _logger;
    private readonly LdapSettings _ldapSettings;
    private readonly LoggingSettings _loggingSettings;

    public LdapAuthenticationService(
        ILogger<LdapAuthenticationService> logger,
        LdapSettings ldapSettings,
        AppSettings appSettings)
    {
        _logger = logger;
        _ldapSettings = ldapSettings;
        _loggingSettings = appSettings.Logging;
    }

    public bool IsLdapEnabled => _ldapSettings.Enabled;

    public bool IsKeymasterFallbackAllowed => _ldapSettings.AllowKeymasterFallback;

    public async Task<AuthenticationResult> AuthenticateAsync(string username, string password)
    {
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password))
        {
            return new AuthenticationResult
            {
                Success = false,
                ErrorMessage = "Username and password are required."
            };
        }

        // Parse username to extract domain and username components
        // Supports: username, DOMAIN\username, username@domain.com
        var (specifiedDomain, parsedUsername) = ParseUsername(username);

        // Determine the effective domain: user-specified or configured default
        var effectiveDomain = specifiedDomain ?? _ldapSettings.Domain;

        // For Keymaster comparison, normalize the username (strip domain/UPN suffix)
        var normalizedUsername = NormalizeUsername(username);

        // Check if this is a Keymaster login attempt
        if (_ldapSettings.AllowKeymasterFallback &&
            normalizedUsername.Equals(_ldapSettings.KeymasterUsername, StringComparison.OrdinalIgnoreCase))
        {
            return await AuthenticateKeymasterAsync(normalizedUsername, password);
        }

        // Try LDAP authentication
        if (_ldapSettings.IsConfigured)
        {
            var ldapResult = await AuthenticateLdapAsync(parsedUsername, password, effectiveDomain, specifiedDomain != null);
            if (ldapResult.Success)
            {
                return ldapResult;
            }

            // If LDAP failed but Keymaster fallback is allowed and this is the Keymaster user, try that
            if (_ldapSettings.AllowKeymasterFallback &&
                normalizedUsername.Equals(_ldapSettings.KeymasterUsername, StringComparison.OrdinalIgnoreCase))
            {
                return await AuthenticateKeymasterAsync(normalizedUsername, password);
            }

            return ldapResult;
        }

        // LDAP not configured - check if Keymaster fallback is available
        if (_ldapSettings.AllowKeymasterFallback)
        {
            if (normalizedUsername.Equals(_ldapSettings.KeymasterUsername, StringComparison.OrdinalIgnoreCase))
            {
                return await AuthenticateKeymasterAsync(normalizedUsername, password);
            }

            return new AuthenticationResult
            {
                Success = false,
                ErrorMessage = "LDAP is not configured. Only the Keymaster account can authenticate."
            };
        }

        return new AuthenticationResult
        {
            Success = false,
            ErrorMessage = "Authentication is not configured."
        };
    }

    private async Task<AuthenticationResult> AuthenticateLdapAsync(string username, string password, string? domain, bool isUpnFormat)
    {
        return await Task.Run(() =>
        {
            try
            {
                // Build the user principal name or domain\username
                string userDn;
                if (isUpnFormat && username.Contains('@'))
                {
                    // UPN format - use as-is for LDAP bind
                    userDn = username;
                    _logger.LogInformation("Authenticating with UPN format: {UserDn}", userDn);
                }
                else if (!string.IsNullOrEmpty(domain))
                {
                    // Domain\username format
                    userDn = $"{domain}\\{username}";
                    _logger.LogInformation("Authenticating with domain: {Domain}", domain);
                }
                else
                {
                    // No domain - use plain username
                    userDn = username;
                    _logger.LogInformation("Authenticating without domain prefix");
                }

                // Create LDAP connection
                var ldapIdentifier = new LdapDirectoryIdentifier(_ldapSettings.Server, _ldapSettings.Port);
                var credential = new NetworkCredential(userDn, password);

                using var connection = new LdapConnection(ldapIdentifier, credential, AuthType.Basic);

                // Configure SSL if enabled
                connection.SessionOptions.SecureSocketLayer = _ldapSettings.UseSsl;
                connection.SessionOptions.ProtocolVersion = 3;

                // Set timeout
                connection.Timeout = TimeSpan.FromSeconds(_ldapSettings.ConnectionTimeout);

                // For LDAPS, we may need to handle certificate validation
                if (_ldapSettings.UseSsl)
                {
                    connection.SessionOptions.VerifyServerCertificate = (conn, cert) => true; // Accept all certs for now
                }

                // Attempt to bind (authenticate)
                connection.Bind();

                _logger.LogInformation("LDAP authentication successful for user {Username}", username);

                // Extract bare username for search filter (strip domain/UPN suffix)
                var searchUsername = username;
                if (searchUsername.Contains('@'))
                {
                    searchUsername = searchUsername.Split('@').First();
                }
                else if (searchUsername.Contains('\\'))
                {
                    searchUsername = searchUsername.Split('\\').Last();
                }

                // Try to get user details
                var displayName = searchUsername;
                string? email = null;
                var groups = new List<string>();

                try
                {
                    // Search for the user to get additional attributes
                    var searchFilter = string.Format(_ldapSettings.UserSearchFilter, searchUsername);
                    _logger.LogInformation("LDAP attribute search: Filter={Filter}, BaseDN={BaseDn}",
                        searchFilter, _ldapSettings.BaseDn);

                    var searchRequest = new SearchRequest(
                        _ldapSettings.BaseDn,
                        searchFilter,
                        SearchScope.Subtree,
                        "displayName", "mail", "memberOf");

                    var searchResponse = (SearchResponse)connection.SendRequest(searchRequest);

                    _logger.LogInformation("LDAP search returned {Count} entries for user {Username}",
                        searchResponse.Entries.Count, searchUsername);

                    if (searchResponse.Entries.Count > 0)
                    {
                        var entry = searchResponse.Entries[0];

                        // Log user DN and available attributes
                        _logger.LogInformation("Found user DN: {UserDn}", entry.DistinguishedName);

                        var attributeNames = new List<string>();
                        foreach (DirectoryAttribute attr in entry.Attributes.Values)
                        {
                            attributeNames.Add($"{attr.Name}({attr.Count})");
                        }
                        _logger.LogInformation("User {Username} returned attributes: [{Attributes}]",
                            searchUsername, string.Join(", ", attributeNames));

                        if (entry.Attributes.Contains("displayName"))
                        {
                            displayName = entry.Attributes["displayName"][0]?.ToString() ?? username;
                        }

                        if (entry.Attributes.Contains("mail"))
                        {
                            email = entry.Attributes["mail"][0]?.ToString();
                        }

                        if (entry.Attributes.Contains("memberOf"))
                        {
                            var memberOfAttr = entry.Attributes["memberOf"];
                            var memberOfCount = memberOfAttr.Count;

                            // Extended logging for group membership details
                            if (_loggingSettings.EnableExtendedLogging)
                            {
                                _logger.LogInformation("User {Username} has {Count} direct group memberships",
                                    searchUsername, memberOfCount);

                                // Log raw value type and first entry for debugging
                                if (memberOfCount > 0)
                                {
                                    var firstValue = memberOfAttr[0];
                                    _logger.LogInformation("memberOf value type: {Type}, first raw value: {Value}",
                                        firstValue?.GetType().Name ?? "null",
                                        firstValue?.ToString() ?? "(null)");
                                }
                            }

                            // Try to extract groups - handle both string and byte[] values
                            for (int i = 0; i < memberOfAttr.Count; i++)
                            {
                                string? groupDn = null;
                                var value = memberOfAttr[i];

                                if (value is string strValue)
                                {
                                    groupDn = strValue;
                                }
                                else if (value is byte[] byteValue)
                                {
                                    groupDn = System.Text.Encoding.UTF8.GetString(byteValue);
                                }
                                else if (value != null)
                                {
                                    groupDn = value.ToString();
                                }

                                if (!string.IsNullOrEmpty(groupDn))
                                {
                                    // Extract just the CN from the DN
                                    var cnMatch = System.Text.RegularExpressions.Regex.Match(groupDn, @"CN=([^,]+)");
                                    if (cnMatch.Success)
                                    {
                                        var groupName = cnMatch.Groups[1].Value;
                                        groups.Add(groupName);
                                    }
                                    else if (i == 0)
                                    {
                                        _logger.LogWarning("Failed to extract CN from group DN: {GroupDn}", groupDn);
                                    }
                                }
                            }

                            // Extended logging for extracted groups
                            if (_loggingSettings.EnableExtendedLogging)
                            {
                                _logger.LogInformation("Extracted {ExtractedCount} groups from {TotalCount} memberOf entries",
                                    groups.Count, memberOfCount);

                                if (groups.Count > 0)
                                {
                                    var sampleGroups = groups.Take(10).ToList();
                                    _logger.LogInformation("User {Username} groups (first 10): [{Groups}]",
                                        searchUsername, string.Join(", ", sampleGroups));
                                }
                            }
                        }
                        else
                        {
                            _logger.LogWarning("User {Username} - memberOf attribute NOT present in LDAP response. " +
                                "Check if the service account has permission to read group memberships.",
                                searchUsername);
                        }
                    }
                    else
                    {
                        _logger.LogWarning("LDAP search returned 0 entries for user {Username}. " +
                            "Check BaseDN ({BaseDn}) and UserSearchFilter ({Filter})",
                            searchUsername, _ldapSettings.BaseDn, searchFilter);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to retrieve user attributes for {Username}: {Message}",
                        username, ex.Message);
                }

                return new AuthenticationResult
                {
                    Success = true,
                    Username = searchUsername,
                    DisplayName = displayName,
                    Email = email,
                    Groups = groups,
                    AuthType = AuthenticationType.Ldap
                };
            }
            catch (LdapException ex)
            {
                _logger.LogWarning("LDAP authentication failed for user {Username}: {Error}", username, ex.Message);

                var errorMessage = ex.ErrorCode switch
                {
                    49 => "Invalid username or password.",
                    81 => "Cannot connect to LDAP server.",
                    _ => $"Authentication failed: {ex.Message}"
                };

                return new AuthenticationResult
                {
                    Success = false,
                    ErrorMessage = errorMessage
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "LDAP authentication error for user {Username}", username);
                return new AuthenticationResult
                {
                    Success = false,
                    ErrorMessage = $"Authentication error: {ex.Message}"
                };
            }
        });
    }

    private async Task<AuthenticationResult> AuthenticateKeymasterAsync(string username, string password)
    {
        return await Task.Run(() =>
        {
            try
            {
                _logger.LogInformation("Attempting Keymaster authentication for user {Username}", username);

                // Use Windows LogonUser API for local authentication
                bool isValid = ValidateWindowsCredentials(username, password);

                if (isValid)
                {
                    _logger.LogInformation("Keymaster authentication successful for user {Username}", username);
                    return new AuthenticationResult
                    {
                        Success = true,
                        Username = username,
                        DisplayName = "Keymaster",
                        AuthType = AuthenticationType.Keymaster,
                        Groups = new List<string> { "Administrators" } // Keymaster gets admin access
                    };
                }

                _logger.LogWarning("Keymaster authentication failed for user {Username}", username);
                return new AuthenticationResult
                {
                    Success = false,
                    ErrorMessage = "Invalid username or password."
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Keymaster authentication error for user {Username}", username);
                return new AuthenticationResult
                {
                    Success = false,
                    ErrorMessage = $"Authentication error: {ex.Message}"
                };
            }
        });
    }

    private bool ValidateWindowsCredentials(string username, string password)
    {
        try
        {
            // Use LogonUser Windows API
            var success = NativeMethods.LogonUser(
                username,
                ".", // Local machine
                password,
                NativeMethods.LOGON32_LOGON_NETWORK,
                NativeMethods.LOGON32_PROVIDER_DEFAULT,
                out var tokenHandle);

            if (success && tokenHandle != IntPtr.Zero)
            {
                NativeMethods.CloseHandle(tokenHandle);
                return true;
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    public async Task<(bool Success, string Message)> TestConnectionAsync()
    {
        if (!_ldapSettings.IsConfigured)
        {
            return (false, "LDAP is not configured.");
        }

        return await Task.Run(() =>
        {
            try
            {
                var ldapIdentifier = new LdapDirectoryIdentifier(_ldapSettings.Server, _ldapSettings.Port);
                using var connection = new LdapConnection(ldapIdentifier);

                connection.SessionOptions.SecureSocketLayer = _ldapSettings.UseSsl;
                connection.SessionOptions.ProtocolVersion = 3;
                connection.Timeout = TimeSpan.FromSeconds(_ldapSettings.ConnectionTimeout);

                if (_ldapSettings.UseSsl)
                {
                    connection.SessionOptions.VerifyServerCertificate = (conn, cert) => true;
                }

                // Try anonymous bind to test connectivity
                connection.AuthType = AuthType.Anonymous;
                connection.Bind();

                return (true, $"Successfully connected to {_ldapSettings.Server}:{_ldapSettings.Port}");
            }
            catch (LdapException ex)
            {
                return (false, $"Connection failed: {ex.Message}");
            }
            catch (Exception ex)
            {
                return (false, $"Connection error: {ex.Message}");
            }
        });
    }

    /// <summary>
    /// Parses a username to extract domain and username components.
    /// Supports formats: username, DOMAIN\username, username@domain.com
    /// </summary>
    /// <param name="input">The raw username input</param>
    /// <returns>Tuple of (domain, username) where domain may be null if not specified</returns>
    private (string? Domain, string Username) ParseUsername(string input)
    {
        input = input.Trim();

        // Format: DOMAIN\username (down-level logon name)
        if (input.Contains('\\'))
        {
            var parts = input.Split('\\', 2);
            var domain = parts[0].Trim();
            var username = parts[1].Trim();
            return (string.IsNullOrEmpty(domain) ? null : domain, username);
        }

        // Format: username@domain.com (UPN format)
        if (input.Contains('@'))
        {
            // For UPN, we use the full string as the username for LDAP bind
            // Extract the domain part for logging/display purposes
            var atIndex = input.LastIndexOf('@');
            var domain = input.Substring(atIndex + 1).Trim();
            // Return the full UPN as username since LDAP can bind with UPN directly
            return (domain, input);
        }

        // Plain username - no domain specified
        return (null, input);
    }

    /// <summary>
    /// Normalizes a username by removing domain prefix (for Keymaster comparison).
    /// </summary>
    private string NormalizeUsername(string username)
    {
        var (_, normalizedUsername) = ParseUsername(username);
        // For Keymaster, strip the UPN suffix if present
        if (normalizedUsername.Contains('@'))
        {
            normalizedUsername = normalizedUsername.Split('@').First();
        }
        return normalizedUsername;
    }
}

/// <summary>
/// Native Windows methods for local authentication.
/// </summary>
internal static class NativeMethods
{
    public const int LOGON32_LOGON_NETWORK = 3;
    public const int LOGON32_PROVIDER_DEFAULT = 0;

    [System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    public static extern bool LogonUser(
        string lpszUsername,
        string lpszDomain,
        string lpszPassword,
        int dwLogonType,
        int dwLogonProvider,
        out IntPtr phToken);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
