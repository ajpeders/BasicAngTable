namespace ClaimAttachmentsApi.Shared
{
    public class OperationInfoLog
    {
        public required string RequestId { get; set; }
        public required string Operation { get; set; }
        public required DateTimeOffset Time { get; set; }
        public required string USUS_ID { get; set; }
        public required string Region { get; set; }
        public required string AppId { get; set; }
        public required string Status { get; set; }
        public string? Message { get; set; }
        public FileInfoLog? FileInfo { get; set; }
    }
}
