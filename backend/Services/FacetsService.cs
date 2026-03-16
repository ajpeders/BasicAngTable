using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using System.Net.Http.Headers;

namespace ClaimAttachmentsApi.Services
{
    public class FacetsService : IFacetsService
    {
        private readonly HttpClient _httpClient;
        private readonly string _claimAccessUrlTemplate;
        private readonly ILogger<FacetsService> _logger;

        public FacetsService(HttpClient httpClient, ILogger<FacetsService> logger)
        {
            _httpClient = httpClient;
            _logger = logger;
            _claimAccessUrlTemplate = Environment.GetEnvironmentVariable("FacetsClaimAccessUrlTemplate")
                ?? string.Empty;
        }

        public async Task<bool> ValidateClaimAccessAsync(string token, string claimId)
        {
            if (string.IsNullOrWhiteSpace(token) || string.IsNullOrWhiteSpace(claimId))
            {
                return false;
            }

            var requestUrl = BuildClaimAccessUrl(claimId);
            var request = new HttpRequestMessage(HttpMethod.Get, requestUrl);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            var response = await _httpClient.SendAsync(request);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Claim access validation denied for claimId {ClaimId}. StatusCode: {StatusCode}",
                    claimId,
                    (int)response.StatusCode);
            }

            return response.IsSuccessStatusCode;
        }

        private string BuildClaimAccessUrl(string claimId)
        {
            if (string.IsNullOrWhiteSpace(_claimAccessUrlTemplate))
            {
                throw new InvalidOperationException("Missing FacetsClaimAccessUrlTemplate environment variable.");
            }

            if (!_claimAccessUrlTemplate.Contains("{claimId}", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "FacetsClaimAccessUrlTemplate must contain the {claimId} placeholder.");
            }

            return _claimAccessUrlTemplate.Replace(
                "{claimId}",
                Uri.EscapeDataString(claimId),
                StringComparison.OrdinalIgnoreCase);
        }

        public Dictionary<string, JsonElement>? ParseTokenClaims(string token)
        {
            if (string.IsNullOrWhiteSpace(token))
            {
                _logger.LogWarning("Unable to parse JWT claims: token is null or empty.");
                return null;
            }

            try
            {
                var parts = token.Split('.');
                if (parts.Length < 2 || string.IsNullOrWhiteSpace(parts[1]))
                {
                    _logger.LogWarning("Unable to parse JWT claims: token payload segment is missing.");
                    return null;
                }

                // JWT payload is base64url encoded, not standard base64.
                var payload = parts[1]
                    .Replace('-', '+')
                    .Replace('_', '/');

                var padded = payload.PadRight(
                    payload.Length + (4 - payload.Length % 4) % 4, '=');
                var json = Encoding.UTF8.GetString(Convert.FromBase64String(padded));
                var claims = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json);
                if (claims is null)
                {
                    _logger.LogWarning("Unable to parse JWT claims: payload deserialized to null.");
                }

                return claims;
            }
            catch (FormatException ex)
            {
                _logger.LogWarning(ex, "Unable to parse JWT claims: payload is not valid base64url.");
                return null;
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Unable to parse JWT claims: payload is not valid JSON.");
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Unable to parse JWT claims due to an unexpected error.");
                return null;
            }
        }
    }
}
