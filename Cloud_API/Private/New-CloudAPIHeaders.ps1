function New-CloudAPIHeaders {
    <#
    .SYNOPSIS
        Creates standardized headers for Cloud API requests.
    
    .DESCRIPTION
        Creates a hashtable with the x-api-key header and optionally includes
        Content-Type and Accept headers. Additional custom headers can be added
        via the AdditionalHeaders parameter.
    
    .PARAMETER IncludeContentType
        If specified, includes the Content-Type header with the default value.
    
    .PARAMETER IncludeAccept
        If specified, includes the Accept header with the default value.
    
    .PARAMETER AdditionalHeaders
        A hashtable of additional headers to include in the request.
    
    .EXAMPLE
        PS> $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept
        
        Creates headers with API key, Content-Type, and Accept headers.
    
    .EXAMPLE
        PS> $headers = New-CloudAPIHeaders -AdditionalHeaders @{'X-Custom-Header' = 'Value'}
        
        Creates headers with API key and a custom header.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$IncludeContentType,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeAccept,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$AdditionalHeaders = @{}
    )
    
    # Ensure API key is available
    if ([string]::IsNullOrWhiteSpace($script:CloudAPIKey)) {
        throw "Cloud API key not initialized. Please run Initialize-CloudAPIConnection or reload the module."
    }
    
    $headers = @{
        'x-api-key' = $script:CloudAPIKey
    }
    
    if ($IncludeContentType) {
        $headers['Content-Type'] = $script:ModuleConfig.DefaultContentType
    }
    
    if ($IncludeAccept) {
        $headers['accept'] = $script:ModuleConfig.DefaultAccept
    }
    
    # Merge additional headers
    foreach ($key in $AdditionalHeaders.Keys) {
        $headers[$key] = $AdditionalHeaders[$key]
    }
    
    return $headers
}
