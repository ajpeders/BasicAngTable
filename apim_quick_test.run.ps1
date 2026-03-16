$TenantId = if ($env:APIM_TENANT_ID) { $env:APIM_TENANT_ID } else { "<tenant-id>" }
$ClientId = if ($env:APIM_CLIENT_ID) { $env:APIM_CLIENT_ID } else { "<client-id>" }
$ClientSecret = if ($env:APIM_CLIENT_SECRET) { $env:APIM_CLIENT_SECRET } else { "REPLACE_WITH_CLIENT_SECRET" }
$Scope = if ($env:APIM_SCOPE) { $env:APIM_SCOPE } else { "api://<app-id-uri>/.default" }
$ApimBaseUrl = if ($env:APIM_BASE_URL) { $env:APIM_BASE_URL } else { "https://<your-apim-host>" }
$ApimSubscriptionKey = if ($env:APIM_SUBSCRIPTION_KEY) { $env:APIM_SUBSCRIPTION_KEY } else { "REPLACE_WITH_APIM_SUBSCRIPTION_KEY" }
$ClaimId = if ($env:APIM_CLAIM_ID) { $env:APIM_CLAIM_ID } else { "REPLACE_WITH_CLCL_ID" }
$Filename = if ($env:APIM_FILENAME) { $env:APIM_FILENAME } else { "test" }
$Directory = if ($env:APIM_DIRECTORY) { $env:APIM_DIRECTORY } else { "test" }
$UploadFilePath = if ($env:APIM_UPLOAD_FILE_PATH) { $env:APIM_UPLOAD_FILE_PATH } else { "" }
$SkipUpload = if ($env:APIM_SKIP_UPLOAD) {
  $env:APIM_SKIP_UPLOAD -in @("1", "true", "True", "TRUE")
} else {
  $true
}

$localOverridesPath = Join-Path $PSScriptRoot "apim_quick_test.local.ps1"
if (Test-Path -LiteralPath $localOverridesPath) {
  . $localOverridesPath
}

function Assert-Configured([string]$name, [string]$value) {
  if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^<.+>$' -or $value -like 'REPLACE_WITH_*') {
    throw "Missing required setting: $name. Set env var or apim_quick_test.local.ps1."
  }
}

Assert-Configured "TenantId/APIM_TENANT_ID" $TenantId
Assert-Configured "ClientId/APIM_CLIENT_ID" $ClientId
Assert-Configured "ClientSecret/APIM_CLIENT_SECRET" $ClientSecret
Assert-Configured "Scope/APIM_SCOPE" $Scope
Assert-Configured "ApimBaseUrl/APIM_BASE_URL" $ApimBaseUrl
Assert-Configured "ApimSubscriptionKey/APIM_SUBSCRIPTION_KEY" $ApimSubscriptionKey
Assert-Configured "ClaimId/APIM_CLAIM_ID" $ClaimId

& "$PSScriptRoot/apim_quick_test.ps1" `
  -TenantId $TenantId `
  -ClientId $ClientId `
  -ClientSecret $ClientSecret `
  -Scope $Scope `
  -ApimBaseUrl $ApimBaseUrl `
  -ApimSubscriptionKey $ApimSubscriptionKey `
  -ClaimId $ClaimId `
  -Filename $Filename `
  -Directory $Directory `
  -UploadFilePath $UploadFilePath `
  -SkipUpload:$SkipUpload
