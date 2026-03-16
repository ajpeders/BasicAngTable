namespace ClaimAttachmentsApi.Shared
{
    public class FileInfoLog
    {
        public string? OriginalFilename { get; init; }
        public string? Filename { get; set; }
        public string? Extension { get; set; }
        public string? OriginalDirectory { get; set; }
        public string? Directory { get; set; }
        public double? SizeMB { get; set; }
        public string? ContentType { get; set; }
    }
}
