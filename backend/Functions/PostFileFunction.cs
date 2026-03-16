using System.IO;
using System.Net;
using Azure;
using ClaimAttachmentsApi.Services;
using ClaimAttachmentsApi.Shared;
using HttpMultipartParser;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace ClaimAttachmentsApi.Functions
{
    public class PostFileFunction
    {
        private readonly ILogger<PostFileFunction> _logger;
        private readonly IFileShareService _fileShareService;
        private readonly IFacetsService _facetsService;

        public PostFileFunction(
            ILogger<PostFileFunction> logger,
            IFileShareService fileShareService,
            IFacetsService facetsService)
        {
            _logger = logger;
            _fileShareService = fileShareService;
            _facetsService = facetsService;
        }

        [Function("Upload")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = "upload")] HttpRequestData req)
        {
            var opLog = new OperationInfoLog
            {
                RequestId = Guid.NewGuid().ToString(),
                Operation = "Upload",
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

                // Parse form
                var parsedForm = await MultipartFormDataParser.ParseAsync(req.Body);

                var rawDirectory = parsedForm.GetParameterValue("dir");
                var directory = FileShareServiceHelpers.SanitizeName(rawDirectory);
                var claimId = (parsedForm.GetParameterValue("claimId")
                    ?? parsedForm.GetParameterValue("clclId"))?.Trim();

                var file = parsedForm.Files.FirstOrDefault();
                var rawFilename = file?.FileName;

                opLog.Time = DateTimeOffset.UtcNow;
                opLog.USUS_ID = FacetsServiceHelpers.GetClaimValue(claims, "facets-ususid", "Unknown");
                opLog.Region = FacetsServiceHelpers.GetClaimValue(claims, "facets-region", "unknown");
                opLog.AppId = FacetsServiceHelpers.GetClaimValue(claims, "facets-appid", "unknown");
                opLog.FileInfo = new FileInfoLog
                {
                    OriginalFilename = rawFilename,
                    Extension = Path.GetExtension(rawFilename),
                    OriginalDirectory = rawDirectory,
                    Directory = directory,
                    SizeMB = FileShareServiceHelpers.GetFileSizeMB(file?.Data.Length),
                    ContentType = file?.ContentType ?? FileShareServiceHelpers.GetContentTypeFromExtension(rawFilename)
                };

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
                    opLog.Message = "Missing claimId in form body";
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

                if (string.IsNullOrWhiteSpace(directory))
                {
                    opLog.Status = "Error";
                    opLog.Message = "Missing directory in body";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(req, HttpStatusCode.BadRequest, opLog);
                }

                if (file is null || file.Data.Length == 0)
                {
                    opLog.Status = "Error";
                    opLog.Message = "Missing or empty file in body";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(req, HttpStatusCode.BadRequest, opLog);
                }
                // Validate file size.
                if (!_fileShareService.ValidateSize(file.Data.Length))
                {
                    opLog.Status = "Error";
                    opLog.Message = "File exceeds max file size";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(req, HttpStatusCode.BadRequest, opLog);
                }

                var shareDirectoryClient = _fileShareService
                    .GetSharedDirectoryClient(directory);

                if (!(await shareDirectoryClient.ExistsAsync()))
                {
                    opLog.Status = "Error";
                    opLog.Message = $"Directory not found: [{directory}]";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning("{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(req, HttpStatusCode.NotFound, opLog);
                }

                var oldFilename = FileShareServiceHelpers.SanitizeName(opLog.FileInfo.OriginalFilename);
                opLog.FileInfo.Extension = Path.GetExtension(oldFilename);
                var filenameNoExt = Path.GetFileNameWithoutExtension(oldFilename);
                string timestamp = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss");

                opLog.FileInfo.Filename = $"{filenameNoExt}_{timestamp}{opLog.FileInfo.Extension}";

                opLog.Status = "Uploading";
                opLog.Time = DateTimeOffset.UtcNow;
                _logger.LogInformation("{@operationLog}", opLog);

                var fileClient = shareDirectoryClient.GetFileClient(opLog.FileInfo.Filename);
                file.Data.Position = 0;
                await fileClient.CreateAsync(file.Data.Length);
                await fileClient.UploadAsync(file.Data);

                opLog.Status = "Complete";
                opLog.Time = DateTimeOffset.UtcNow;
                _logger.LogInformation("{@operationLog}", opLog);

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new
                {
                    success = true,
                    requestId = opLog.RequestId,
                    filename = opLog.FileInfo.Filename,
                    data = opLog.FileInfo,
                    time = DateTimeOffset.UtcNow
                });
                return res;
                }
                catch (RequestFailedException azEx) when (azEx.Status == 404)
                {
                    opLog.Status = "Error";
                    opLog.Message = "Resource not found";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogWarning(azEx, "{@operationInfo} | AzureErrorCode: {AzureErrorCode}", opLog, azEx.ErrorCode);
                    return await _fileShareService.CreateErrorResponseAsync(req, HttpStatusCode.NotFound, opLog);
                }

                catch (Exception ex)
                {
                    opLog.Status = "Error";
                    opLog.Message = "Unexpected server error";
                    opLog.Time = DateTimeOffset.UtcNow;
                    _logger.LogError(ex, "{@operationInfo}", opLog);
                    return await _fileShareService.CreateErrorResponseAsync(req, HttpStatusCode.InternalServerError, opLog);
                }
            }
        }
    }
