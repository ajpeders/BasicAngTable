param(
  [string]$TenantId = "<tenant-id>",
  [string]$ClientId = "<client-id>",
  [string]$ClientSecret,
  [string]$Scope = "api://<app-id-uri>/.default",
  [string]$ApimBaseUrl = "https://<your-apim-host>",
  [string]$ApimSubscriptionKey,
  [string]$ClaimId = "TEST-CLAIM-ID",
  [string]$Filename = "test",
  [string]$Directory = "test",
  [string]$UploadFilePath = "",
  [switch]$SkipUpload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Exit-WithError([string]$message) {
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

function Read-HttpErrorBody([System.Management.Automation.ErrorRecord]$err) {
  try {
    $response = $err.Exception.Response
    if ($null -eq $response) { return "" }

    $stream = $response.GetResponseStream()
    if ($null -eq $stream) { return "" }

    $reader = New-Object System.IO.StreamReader($stream)
    return $reader.ReadToEnd()
  } catch {
    return ""
  }
}

if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
  Exit-WithError "Missing -ClientSecret."
}

if ([string]::IsNullOrWhiteSpace($ApimSubscriptionKey)) {
  Exit-WithError "Missing -ApimSubscriptionKey."
}

$apimBase = $ApimBaseUrl.TrimEnd("/")
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

Write-Host "Requesting Azure AD token..." -ForegroundColor Cyan
$tokenResponse = Invoke-RestMethod `
  -Method Post `
  -Uri $tokenUrl `
  -ContentType "application/x-www-form-urlencoded" `
  -Body @{
    grant_type = "client_credentials"
    client_id = $ClientId
    client_secret = $ClientSecret
    scope = $Scope
  }

$accessToken = $tokenResponse.access_token
if ([string]::IsNullOrWhiteSpace($accessToken)) {
  Exit-WithError "Token response did not include access_token."
}

Write-Host "Token acquired." -ForegroundColor Green

$headers = @{
  Authorization = "Bearer $accessToken"
  "Ocp-Apim-Subscription-Key" = $ApimSubscriptionKey
}

$encodedFilename = [System.Uri]::EscapeDataString($Filename)
$encodedDirectory = [System.Uri]::EscapeDataString($Directory)
$encodedClaimId = [System.Uri]::EscapeDataString($ClaimId)
$getUrl = "$apimBase/facets/GetFile?filename=$encodedFilename&dir=$encodedDirectory&claimId=$encodedClaimId"

Write-Host "Testing GET $getUrl" -ForegroundColor Cyan
try {
  $getResponse = Invoke-WebRequest -Method Get -Uri $getUrl -Headers $headers
  Write-Host ("GET status: {0}" -f [int]$getResponse.StatusCode) -ForegroundColor Green
  if ($getResponse.Headers["Content-Type"]) {
    Write-Host ("GET content-type: {0}" -f $getResponse.Headers["Content-Type"])
  }
  if ($getResponse.Headers["Content-Length"]) {
    Write-Host ("GET content-length: {0}" -f $getResponse.Headers["Content-Length"])
  }
} catch {
  $statusCode = ""
  try {
    $statusCode = [int]$_.Exception.Response.StatusCode
  } catch {}

  $body = Read-HttpErrorBody $_
  Write-Host ("GET failed. Status: {0}" -f $statusCode) -ForegroundColor Yellow
  if (-not [string]::IsNullOrWhiteSpace($body)) {
    Write-Host $body
  }
}

if ($SkipUpload) {
  Write-Host "Upload test skipped (-SkipUpload)." -ForegroundColor Yellow
  exit 0
}

if ([string]::IsNullOrWhiteSpace($UploadFilePath)) {
  Write-Host "Upload not run. Provide -UploadFilePath or use -SkipUpload." -ForegroundColor Yellow
  exit 0
}

if (-not (Test-Path -LiteralPath $UploadFilePath)) {
  Exit-WithError "Upload file path does not exist: $UploadFilePath"
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
  Exit-WithError "Upload test requires PowerShell 7+ (Invoke-WebRequest -Form). Use -SkipUpload on Windows PowerShell 5.1."
}

$uploadUrl = "$apimBase/facets/upload"
Write-Host "Testing POST $uploadUrl" -ForegroundColor Cyan
try {
  $uploadResponse = Invoke-WebRequest `
    -Method Post `
    -Uri $uploadUrl `
    -Headers $headers `
    -Form @{
      dir = $Directory
      claimId = $ClaimId
      file = Get-Item -LiteralPath $UploadFilePath
    }

  Write-Host ("POST status: {0}" -f [int]$uploadResponse.StatusCode) -ForegroundColor Green
  if (-not [string]::IsNullOrWhiteSpace($uploadResponse.Content)) {
    Write-Host "POST response body:"
    Write-Host $uploadResponse.Content
  }
} catch {
  $statusCode = ""
  try {
    $statusCode = [int]$_.Exception.Response.StatusCode
  } catch {}

  $body = Read-HttpErrorBody $_
  Write-Host ("POST failed. Status: {0}" -f $statusCode) -ForegroundColor Yellow
  if (-not [string]::IsNullOrWhiteSpace($body)) {
    Write-Host $body
  }
}
