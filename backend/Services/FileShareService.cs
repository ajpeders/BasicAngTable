using System.Net;
using Azure.Storage.Files.Shares;
using ClaimAttachmentsApi.Shared;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace ClaimAttachmentsApi.Services
{
    public class FileShareService : IFileShareService
    {
        private readonly string _fileshareConnectionString;
        private readonly string _fileShareName;
        private readonly int _maxFileSizeMB;
        private readonly ShareClient _shareClient;
        private readonly ILogger<FileShareService> _logger;

        public FileShareService(ILogger<FileShareService> logger)
        {
            _logger = logger;
            _fileshareConnectionString = Environment.GetEnvironmentVariable("FileshareConnectionString")
                ?? throw new NullReferenceException("Missing \"FileshareConnectionString\"");

            _fileShareName = Environment.GetEnvironmentVariable("FileshareName")
                ?? throw new NullReferenceException("Missing \"Fileshare\"");

            if (!int.TryParse(Environment.GetEnvironmentVariable("MaxFileSizeMB"), out _maxFileSizeMB))
            {
                _maxFileSizeMB = 50;
                _logger.LogWarning("MaxFileSizeMB is missing or invalid. Using default of {DefaultMaxFileSizeMB} MB.", _maxFileSizeMB);
            }

            _shareClient = new ShareServiceClient(_fileshareConnectionString)
                .GetShareClient(_fileShareName);
        }

        public async Task<HttpResponseData> CreateErrorResponseAsync(
            HttpRequestData req,
            HttpStatusCode statusCode,
            OperationInfoLog opLog)
        {
            var res = req.CreateResponse(statusCode);
            var errorRes = new
            {
                code = statusCode.ToString(),
                message = opLog.Message,
                requestId = opLog.RequestId,
                time = opLog.Time,
                ususId = opLog.USUS_ID,
                region = opLog.Region,
                FileInfo = opLog.FileInfo
            };
            await res.WriteAsJsonAsync(errorRes);
            return res;
        }

        public ShareDirectoryClient GetSharedDirectoryClient(string directory)
        {
            return _shareClient.GetDirectoryClient($"{directory}");
        }

        public bool ValidateSize(long fileSizeBytes)
        {
            if (fileSizeBytes <= 0) return false;
            var fileSizeMB = FileShareServiceHelpers.GetFileSizeMB(fileSizeBytes);
            return fileSizeMB <= _maxFileSizeMB;
        }
    }
}
