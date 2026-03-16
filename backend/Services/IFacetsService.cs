using System.Text.Json;

namespace ClaimAttachmentsApi.Services
{
    public interface IFacetsService
    {
        Task<bool> ValidateClaimAccessAsync(string token, string claimId);
        Dictionary<string, JsonElement>? ParseTokenClaims(string token);
    }
}
