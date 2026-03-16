using System.Text.Json;

namespace ClaimAttachmentsApi.Services
{
    public static class FacetsServiceHelpers
    {
        public static string GetClaimValue(
            IReadOnlyDictionary<string, JsonElement>? claims,
            string claimName,
            string fallback)
        {
            if (claims is null || !claims.TryGetValue(claimName, out var claim))
            {
                return fallback;
            }

            return claim.ValueKind switch
            {
                JsonValueKind.String => string.IsNullOrWhiteSpace(claim.GetString()) ? fallback : claim.GetString()!,
                JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False => claim.ToString(),
                _ => fallback
            };
        }
    }
}
