using System.IO;
using System.Net;
using System.Web;
using Azure;
using ClaimAttachmentsApi.Services;
using ClaimAttachmentsApi.Shared;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace ClaimAttachmentsApi.Functions
{
    public class GetFileFunction
    {
        private readonly ILogger<GetFileFunction> _logger;
        private readonly IFileShareService _fileShareService;
        private readonly IFacetsService _facetsService;

        public GetFileFunction(
            ILogger<GetFileFunction> logger,
            IFileShareService fileShareService,
            IFacetsService facetsService
        )
        {
            _logger = logger;
            _fileShareService = fileShareService;
            _facetsService = facetsService;
        }

        [Function("GetFile")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get")] HttpRequestData req)
        {
            var opLog = new OperationInfoLog
            {
                RequestId = Guid.NewGuid().ToString(),
                Operation = "download",
                Time = DateTimeOffset.UtcNow,
                USUS_ID = "Unknown",
                Region = "unknown",
                AppId = "unknown",
                Status = "Started",
                FileInfo = null
            };

            try
            {
                // Parse token.
                string? token = null;
                if (req.Headers.TryGetValues("Authorization", out var authHeaders))
                {
                    var authHeader = authHeaders.FirstOrDefault();
                    if (!string.IsNullOrWhiteSpace(authHeader))
                    {
                        token = authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
                            ? authHeader["Bearer ".Length..].Trim()
                            : authHeader.Trim();
                    }
                }
                var claims = token is not null ? _facetsService.ParseTokenClaims(token) : null;

                // Parse query.
                var query = HttpUtility.ParseQueryString(req.Url.Query);

                var rawFilename = query["filename"];
                var rawDirectory = query["dir"];
                var rawClaimId = query["claimId"] ?? query["clclId"];

                var filename = FileShareServiceHelpers.SanitizeName(rawFilename);
                var directory = FileShareServiceHelpers.SanitizeName(rawDirectory);
                var claimId = rawClaimId?.Trim();

                opLog.USUS_ID = FacetsServiceHelpers.GetClaimValue(claims, "facets-ususid", "Unknown");
                opLog.Region = FacetsServiceHelpers.GetClaimValue(claims, "facets-region", "unknown");
                opLog.AppId = FacetsServiceHelpers.GetClaimValue(claims, "facets-appid", "unknown");
                opLog.FileInfo = new FileInfoLog
                {
                    OriginalFilename = rawFilename ?? "Unknown",
                    Filename = filename,
                    Extension = Path.GetExtension(filename),
                    OriginalDirectory = rawDirectory ?? "unknown",
                    Directory = directory,
                };

                if (string.IsNullOrWhiteSpace(rawFilename))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Missing filename query parameter";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.BadRequest, opLog);
                }

                if (string.IsNullOrWhiteSpace(rawDirectory))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Missing dir query parameter";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.BadRequest, opLog);
                }

                if (string.IsNullOrWhiteSpace(filename))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Invalid filename query parameter";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.BadRequest, opLog);
                }

                if (string.IsNullOrWhiteSpace(directory))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Invalid dir query parameter";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.BadRequest, opLog);
                }

                _logger.LogInformation("{@operationInfo}", opLog);

                // ========
                // Authorize file access.
                // ========

                if (string.IsNullOrWhiteSpace(token))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Unauthorized - missing bearer token";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.Unauthorized, opLog);
                }

                if (string.IsNullOrWhiteSpace(claimId))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Missing claimId query parameter";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.BadRequest, opLog);
                }

                try
                {
                    var hasClaimAccess = await _facetsService.ValidateClaimAccessAsync(token, claimId);
                    if (!hasClaimAccess)
                    {
                        opLog.Status = "Error";
                        opLog.Message = $"Forbidden - no access to claimId [{claimId}]";
                        opLog.Time = DateTimeOffset.UtcNow;
                        _logger.LogWarning("{@operationInfo}", opLog);
                        return await _fileShareService.CreateErrorResponseAsync(
                            req, HttpStatusCode.Forbidden, opLog);
                    }
                }
                catch (Exception ex)
                {
                    opLog.Status = "Error";
                    opLog.Message = "Facets claim access validation failed";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning(ex, "{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.BadGateway, opLog);
                }

                // ========
                // Get File
                // ========

                // Get directory.
                var shareDirectoryClient = _fileShareService
                    .GetSharedDirectoryClient(directory);

                if (!(await shareDirectoryClient.ExistsAsync()))
                {
                    opLog.Status = "Error";
                    opLog.Message = $"Directory not found: [{directory}]";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationLog}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.NotFound, opLog);
                }

                // Get file
                var fileClient = shareDirectoryClient.GetFileClient(filename);
                if (!(await fileClient.ExistsAsync()))
                {
                    opLog.Status = "Error";
                    opLog.Message = $"File not found: [{filename}]";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationLog}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(
                        req, HttpStatusCode.NotFound, opLog);
                }

                var fileProperties = await fileClient.GetPropertiesAsync();
                opLog.FileInfo.SizeMB = FileShareServiceHelpers.GetFileSizeMB(fileProperties.Value.ContentLength);
                opLog.FileInfo.ContentType = fileProperties.Value.ContentType;

                if (string.IsNullOrWhiteSpace(opLog.FileInfo.ContentType) || opLog.FileInfo.ContentType == "application/octet-stream")
                {
                    opLog.FileInfo.ContentType = FileShareServiceHelpers.GetContentTypeFromExtension(filename);
                }

                // Start download.
                opLog.Status = "Downloading";
                opLog.Time = DateTimeOffset.UtcNow;
                _logger.LogInformation("{@operationLog}", opLog);

                var download = await fileClient.DownloadAsync();

                bool isInline = FileShareServiceHelpers.ShouldDisplayInline(filename);

                opLog.Status = "Complete";
                opLog.Time = DateTimeOffset.UtcNow;
                _logger.LogInformation("{@operationLog}", opLog);

                var res = req.CreateResponse(HttpStatusCode.OK);
                res.Headers.Add("Content-Type", opLog.FileInfo.ContentType);
                res.Headers.Add("Content-Disposition", isInline
                    ? $"inline; filename=\"{filename}\""
                    : $"attachment; filename=\"{filename}\"");
                res.Headers.Add("Content-Length",
                    fileProperties.Value.ContentLength.ToString());

                await download.Value.Content.CopyToAsync(res.Body);
                return res;
            }
            catch (RequestFailedException azEx) when (azEx.Status == 404)
            {
                opLog.Status = "Error";
                opLog.Message = "Resource not found";
                opLog.Time = DateTimeOffset.UtcNow;
                _logger.LogWarning(azEx, "{@operationLog} | AzureErrorCode: {AzureErrorCode}", opLog, azEx.ErrorCode);
                return await _fileShareService.CreateErrorResponseAsync(
                    req, HttpStatusCode.NotFound, opLog);
            }

            catch (Exception ex)
            {
                opLog.Status = "Error";
                opLog.Message = "Unexpected server error";
                opLog.Time = DateTimeOffset.UtcNow;
                _logger.LogError(ex, "{@operationInfo}", opLog);
                return await _fileShareService.CreateErrorResponseAsync(
                    req, HttpStatusCode.InternalServerError, opLog);
            }
        }

    }
}
