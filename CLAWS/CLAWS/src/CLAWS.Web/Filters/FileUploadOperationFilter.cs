using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace CLAWS.Web.Filters;

/// <summary>
/// Swagger operation filter to document file upload endpoints that use streaming.
/// </summary>
public class FileUploadOperationFilter : IOperationFilter
{
    public void Apply(OpenApiOperation operation, OperationFilterContext context)
    {
        // Check if the endpoint has DisableFormValueModelBinding attribute
        var hasDisableModelBinding = context.MethodInfo
            .GetCustomAttributes(typeof(DisableFormValueModelBindingAttribute), false)
            .Any();

        if (!hasDisableModelBinding)
            return;

        // Check if it's a POST method (likely file upload)
        var httpMethod = context.ApiDescription.HttpMethod;
        if (!string.Equals(httpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            return;

        // Clear any existing request body and parameters
        operation.RequestBody = new OpenApiRequestBody
        {
            Description = "ZIP file containing SQLite database to upload",
            Required = true,
            Content = new Dictionary<string, OpenApiMediaType>
            {
                ["multipart/form-data"] = new OpenApiMediaType
                {
                    Schema = new OpenApiSchema
                    {
                        Type = "object",
                        Required = new HashSet<string> { "file" },
                        Properties = new Dictionary<string, OpenApiSchema>
                        {
                            ["autoProcessingOverride"] = new OpenApiSchema
                            {
                                Type = "string",
                                Description = "Override auto-processing behavior for this upload. If not specified, uses global settings.",
                                Nullable = true,
                                Enum = new List<Microsoft.OpenApi.Any.IOpenApiAny>
                                {
                                    new Microsoft.OpenApi.Any.OpenApiString(""),
                                    new Microsoft.OpenApi.Any.OpenApiString("ValidateOnly"),
                                    new Microsoft.OpenApi.Any.OpenApiString("ValidateAndMerge"),
                                    new Microsoft.OpenApi.Any.OpenApiString("Manual")
                                }
                            },
                            ["file"] = new OpenApiSchema
                            {
                                Type = "string",
                                Format = "binary",
                                Description = "ZIP file to upload (max 3 GB)"
                            }
                        }
                    }
                }
            }
        };
    }
}
