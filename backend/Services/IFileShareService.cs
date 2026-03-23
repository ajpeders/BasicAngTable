using System.Net;
using Azure.Storage.Files.Shares;
using ClaimAttachmentsApi.Shared;
using Microsoft.Azure.Functions.Worker.Http;

namespace ClaimAttachmentsApi.Services
{
    public interface IFileShareService
    {
        Task<HttpResponseData> CreateErrorResponseAsync(HttpRequestData req, HttpStatusCode statusCode, OperationInfoLog opLog);
        ShareClient GetShareClient();
        ShareDirectoryClient GetSharedDirectoryClient(string directory);
        bool ValidateSize(long fileSizeBytes);
    }
}
