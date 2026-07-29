function Format-CloudAPIError {
    <#
    .SYNOPSIS
        Maps HTTP status codes to user-friendly error messages.
    
    .DESCRIPTION
        Takes an exception object and extracts the HTTP status code to provide
        a user-friendly error message. Returns an object with StatusCode,
        Message, and OriginalException properties.
    
    .PARAMETER Exception
        The exception object from a failed API call.
    
    .EXAMPLE
        PS> try { Invoke-RestMethod ... } catch { $error = Format-CloudAPIError -Exception $_.Exception }
        
        Formats the error from a failed API call.
    
    .OUTPUTS
        PSCustomObject with StatusCode, Message, and OriginalException properties.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Exception]$Exception
    )
    
    # Try to extract status code from various exception types
    $statusCode = $null
    
    if ($Exception.Response) {
        # WebException with Response
        try {
            $statusCode = [int]$Exception.Response.StatusCode
        }
        catch {
            $statusCode = $null
        }
    }
    
    # Map status codes to messages
    $errorMessage = switch ($statusCode) {
        400 { "Bad Request - The request was malformed or missing required parameters." }
        401 { "Unauthorized - Invalid or expired API key. Please verify your credentials." }
        403 { "Forbidden - You don't have permission to perform this action." }
        404 { "Not Found - The requested resource does not exist." }
        405 { "Method Not Allowed - The HTTP method is not supported for this endpoint." }
        409 { "Conflict - The request conflicts with the current state of the resource." }
        422 { "Unprocessable Entity - The request was well-formed but contains semantic errors." }
        429 { "Too Many Requests - Rate limit exceeded. Please wait before retrying." }
        500 { "Internal Server Error - The API server encountered an error." }
        502 { "Bad Gateway - The API gateway received an invalid response." }
        503 { "Service Unavailable - The API service is temporarily unavailable." }
        504 { "Gateway Timeout - The API gateway timed out waiting for a response." }
        default { 
            if ($null -ne $statusCode) {
                "HTTP Error $statusCode - $($Exception.Message)"
            } else {
                $Exception.Message
            }
        }
    }
    
    return [PSCustomObject]@{
        StatusCode = $statusCode
        Message = $errorMessage
        OriginalException = $Exception
    }
}
