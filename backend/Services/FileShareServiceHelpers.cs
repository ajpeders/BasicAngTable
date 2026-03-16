namespace ClaimAttachmentsApi.Services
{
    public class FileShareServiceHelpers
    {
        public static string SanitizeName(string? name)
        {
            if (string.IsNullOrWhiteSpace(name)) return string.Empty;

            // Remove invalid chars.
            var invalid = Path.GetInvalidFileNameChars()
                .Concat(new[] { '/', '\\' })
                .ToArray();

            var sanitized = string.Join("",
                name.Split(invalid, StringSplitOptions.RemoveEmptyEntries));

            sanitized = sanitized.Replace("..", "");

            // Azure file share max filename length is 255
            if (sanitized.Length > 255)
                sanitized = sanitized[..255];

            return sanitized.Trim();
        }

        public static double GetFileSizeMB(long? sizeBytes)
        {
            if (sizeBytes is null or <= 0) return 0;
            return Math.Round((double)sizeBytes / (1024.0 * 1024.0), 2);
        }

        public static string GetContentTypeFromExtension(string? filename)
        {
            if (filename is null) return string.Empty;
            var extension = Path.GetExtension(filename).ToLowerInvariant();

            return extension switch
            {
                ".pdf" => "application/pdf",
                ".doc" => "application/msword",
                ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                ".xls" => "application/vnd.ms-excel",
                ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                ".png" => "image/png",
                ".jpg" or ".jpeg" => "image/jpeg",
                ".gif" => "image/gif",
                ".bmp" => "image/bmp",
                ".webp" => "image/webp",
                ".svg" => "image/svg+xml",
                ".txt" => "text/plain",
                ".csv" => "text/csv",
                ".json" => "application/json",
                ".xml" => "application/xml",
                ".zip" => "application/zip",
                ".mp4" => "video/mp4",
                ".webm" => "video/webm",
                ".mp3" => "audio/mpeg",
                ".wav" => "audio/wav",
                _ => "application/octet-stream"
            };
        }

        public static bool ShouldDisplayInline(string filename)
        {
            var extension = Path.GetExtension(filename).ToLowerInvariant();

            return extension switch
            {
                ".pdf" => true,
                ".txt" => true,
                ".json" => true,
                ".xml" => true,
                ".csv" => true,

                ".png" => true,
                ".jpg" => true,
                ".jpeg" => true,
                ".gif" => true,
                ".bmp" => true,
                ".webp" => true,

                ".mp3" => true,
                ".wav" => true,
                ".ogg" => true,

                _ => false
            };
        }
    }
}
