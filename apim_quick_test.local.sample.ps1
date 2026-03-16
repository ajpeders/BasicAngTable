# Copy this file to apim_quick_test.local.ps1 and set real values locally.
# apim_quick_test.local.ps1 is gitignored to avoid committing secrets.

$TenantId = "<tenant-id>"
$ClientId = "<client-id>"
$ClientSecret = "REPLACE_WITH_CLIENT_SECRET"
$Scope = "api://<app-id-uri>/.default"
$ApimBaseUrl = "https://<your-apim-host>"
$ApimSubscriptionKey = "REPLACE_WITH_APIM_SUBSCRIPTION_KEY"
$ClaimId = "REPLACE_WITH_CLCL_ID"
$Filename = "test"
$Directory = "test"
$UploadFilePath = ""
$SkipUpload = $true
