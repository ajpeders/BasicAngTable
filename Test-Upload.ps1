<#
.SYNOPSIS
    Tests the Upload Azure Function end-to-end against the local environment.

.DESCRIPTION
    Exercises upload scenarios against the local Function App (localhost:7071).
    Also walks through the Facets SP invoke registration chain that the Angular
    component executes after a successful upload.

.PARAMETER FunctionBaseUrl
    Base URL of the Function App. Defaults to local dev.

.PARAMETER FunctionCode
    Function host key. Leave empty when using APIM (subscription key auth only).

.PARAMETER ApimSubscriptionKey
    APIM subscription key. Leave empty when hitting the Function App directly.

.PARAMETER MockFacetsBaseUrl
    Base URL of the mock Facets server for SP invoke calls.

.EXAMPLE
    # Local E2E (all services running)
    .\Test-Upload.ps1

.EXAMPLE
    # Against real APIM
    .\Test-Upload.ps1 `
        -FunctionBaseUrl "https://your-apim.azure-api.net/facets" `
        -FunctionCode "" `
        -ApimSubscriptionKey "your-sub-key-here" `
        -MockFacetsBaseUrl "http://localhost:3001"
#>
param(
    [string] $FunctionBaseUrl     = "http://localhost:7071/api",
    [string] $FunctionCode        = "localkey",
    [string] $ApimSubscriptionKey = "",
    [string] $MockFacetsBaseUrl   = "http://localhost:3001",
    [string] $ClaimId             = "TEST-CLAIM-001",
    [string] $Directory           = "TESTDIR"
)

# ─── Helpers ────────────────────────────────────────────────────────────────

function Write-Result([string]$label, [bool]$pass, [string]$detail = "") {
    $status = if ($pass) { "PASS" } else { "FAIL" }
    $color  = if ($pass) { "Green" } else { "Red" }
    Write-Host "  [$status] $label" -ForegroundColor $color
    if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
}

function New-FakeJwt {
    $header  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"alg":"HS256","typ":"JWT"}')) -replace '=+$','' -replace '\+','-' -replace '/','_'
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"facets-ususid":"TESTUSER","facets-region":"LOCAL","facets-appid":"test"}')) -replace '=+$','' -replace '\+','-' -replace '/','_'
    return "$header.$payload.fakesig"
}

function Build-AuthHeaders([string]$token) {
    $h = @{ Authorization = "Bearer $token" }
    if ($ApimSubscriptionKey) { $h["Ocp-Apim-Subscription-Key"] = $ApimSubscriptionKey }
    return $h
}

function Invoke-SpInvoke([string]$procedure, [hashtable]$parameters = @{}) {
    $body = @{ Procedure = $procedure; Parameters = $parameters; Analyze = $false; Identity = "SVCAGENT" } | ConvertTo-Json
    return Invoke-RestMethod -Uri "$MockFacetsBaseUrl/data/procedure/execute" `
        -Method Post -ContentType "application/json" -Body $body
}

function Build-UploadUrl {
    $url = "$FunctionBaseUrl/upload"
    if ($FunctionCode) { $url += "?code=$FunctionCode" }
    return $url
}

$token  = New-FakeJwt
$passed = 0
$failed = 0

Write-Host ""
Write-Host "Upload + Facets Registration E2E Tests" -ForegroundColor Cyan
Write-Host "  Function : $FunctionBaseUrl"
Write-Host "  Facets   : $MockFacetsBaseUrl"
Write-Host "  ClaimId  : $ClaimId"
Write-Host ""

# ─── Test 1: Successful upload ───────────────────────────────────────────────
Write-Host "1. Successful file upload" -ForegroundColor Yellow
$uploadedFilename = $null
try {
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, "E2E test attachment content`nCreated: $(Get-Date -Format o)`n")
    $tmpFileInfo = Get-Item $tmpFile
    # Rename to give it a meaningful extension
    $srcFile = [System.IO.Path]::ChangeExtension($tmpFile, ".txt")
    Move-Item $tmpFile $srcFile -Force

    # Build multipart form manually using HttpClient
    Add-Type -AssemblyName System.Net.Http
    $client    = [System.Net.Http.HttpClient]::new()
    $form      = [System.Net.Http.MultipartFormDataContent]::new()
    $fileBytes = [System.IO.File]::ReadAllBytes($srcFile)
    $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/plain")
    $form.Add($fileContent, "file", [System.IO.Path]::GetFileName($srcFile))
    $form.Add([System.Net.Http.StringContent]::new($Directory), "dir")
    $form.Add([System.Net.Http.StringContent]::new($ClaimId), "claimId")

    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Build-UploadUrl))
    $req.Headers.Add("Authorization", "Bearer $token")
    if ($ApimSubscriptionKey) { $req.Headers.Add("Ocp-Apim-Subscription-Key", $ApimSubscriptionKey) }
    $req.Content = $form

    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json

    $ok = ($resp.StatusCode.value__ -eq 200) -and ($body.success -eq $true)
    Write-Result "HTTP 200 success=true" $ok "StatusCode=$($resp.StatusCode.value__) success=$($body.success)"

    $hasFilename = ![string]::IsNullOrEmpty($body.filename)
    Write-Result "Response includes timestamped filename" $hasFilename "filename=$($body.filename)"

    $uploadedFilename = $body.filename
    if ($ok -and $hasFilename) { $passed += 2 } else { $failed += 2 }

    Remove-Item $srcFile -ErrorAction SilentlyContinue
    $client.Dispose()
} catch {
    Write-Result "Upload request" $false $_.Exception.Message
    $failed += 2
}

# ─── Test 2: Upload — missing token → 401 ────────────────────────────────────
Write-Host ""
Write-Host "2. Upload — missing bearer token" -ForegroundColor Yellow
try {
    Add-Type -AssemblyName System.Net.Http
    $client  = [System.Net.Http.HttpClient]::new()
    $form    = [System.Net.Http.MultipartFormDataContent]::new()
    $form.Add([System.Net.Http.StringContent]::new($Directory), "dir")
    $form.Add([System.Net.Http.StringContent]::new($ClaimId), "claimId")
    $resp = $client.PostAsync((Build-UploadUrl), $form).GetAwaiter().GetResult()
    Write-Result "HTTP 401" ($resp.StatusCode.value__ -eq 401) "Got $($resp.StatusCode.value__)"
    if ($resp.StatusCode.value__ -eq 401) { $passed++ } else { $failed++ }
    $client.Dispose()
} catch {
    Write-Result "401 check" $false $_.Exception.Message
    $failed++
}

# ─── Test 3: Upload — bad claimId → 403 ──────────────────────────────────────
Write-Host ""
Write-Host "3. Upload — bad claimId (Facets denies access)" -ForegroundColor Yellow
try {
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, "bad claim test")
    Add-Type -AssemblyName System.Net.Http
    $client   = [System.Net.Http.HttpClient]::new()
    $form     = [System.Net.Http.MultipartFormDataContent]::new()
    $fileContent = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($tmpFile))
    $form.Add($fileContent, "file", "test.txt")
    $form.Add([System.Net.Http.StringContent]::new($Directory), "dir")
    $form.Add([System.Net.Http.StringContent]::new("BADCLAIM-999"), "claimId")
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Build-UploadUrl))
    $req.Headers.Add("Authorization", "Bearer $token")
    $req.Content = $form
    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    Write-Result "HTTP 403" ($resp.StatusCode.value__ -eq 403) "Got $($resp.StatusCode.value__)"
    if ($resp.StatusCode.value__ -eq 403) { $passed++ } else { $failed++ }
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
    $client.Dispose()
} catch {
    Write-Result "403 check" $false $_.Exception.Message
    $failed++
}

# ─── Test 4: Facets registration SP invoke chain ─────────────────────────────
Write-Host ""
Write-Host "4. Facets registration SP invoke chain (what the Angular component does after upload)" -ForegroundColor Yellow

$atxrSrc = "2024-01-15T10:30:00"   # matches DataIO shim's CLCL ATXR_SOURCE_ID

try {
    # Generate ATXR IDs for the attachment record
    $genResp = Invoke-SpInvoke "CERSP_ATTO_SELECT_GEN_IDS" @{
        ATXR_SOURCE_ID = $atxrSrc; ATSY_ID = "ATDT"; ATXR_DEST_ID = "1753-01-01T00:00:00"
    }
    $atxrDest = $genResp.Data.ResultSets[0].Rows[0].COL3
    Write-Result "CERSP_ATTO_SELECT_GEN_IDS — got ATXR_DEST_ID" (![string]::IsNullOrEmpty($atxrDest)) "ATXR_DEST_ID=$atxrDest"
    if (![string]::IsNullOrEmpty($atxrDest)) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATTO_SELECT_GEN_IDS" $false $_.Exception.Message; $failed++
}

foreach ($proc in @("CERSP_ATDT_APPLY", "CERSP_ATXR_APPLY", "CERSP_ATNT_APPLY", "CERSP_ATND_APPLY", "CMCSP_CLCL_APPLY")) {
    try {
        $r = Invoke-SpInvoke $proc
        $ok = $null -ne $r.Data.ResultSets
        Write-Result "$proc" $ok
        if ($ok) { $passed++ } else { $failed++ }
    } catch {
        Write-Result "$proc" $false $_.Exception.Message; $failed++
    }
}

# ─── Test 5: Verify uploaded file is downloadable ────────────────────────────
Write-Host ""
Write-Host "5. Uploaded file is retrievable via GetFile" -ForegroundColor Yellow
if ($uploadedFilename) {
    try {
        $url = "$FunctionBaseUrl/GetFile?filename=$([Uri]::EscapeDataString($uploadedFilename))&dir=$([Uri]::EscapeDataString($Directory))&claimId=$([Uri]::EscapeDataString($ClaimId))"
        if ($FunctionCode) { $url += "&code=$FunctionCode" }
        $resp = Invoke-WebRequest -Uri $url -Headers (Build-AuthHeaders $token) -UseBasicParsing
        Write-Result "HTTP 200 on GetFile for just-uploaded file" ($resp.StatusCode -eq 200) "StatusCode=$($resp.StatusCode) Bytes=$($resp.Content.Length)"
        if ($resp.StatusCode -eq 200) { $passed++ } else { $failed++ }
    } catch {
        Write-Result "GetFile for uploaded file" $false $_.Exception.Message; $failed++
    }
} else {
    Write-Host "  [SKIP] Upload failed, skipping download verification" -ForegroundColor DarkYellow
}

# ─── Test 6: Missing dir → 400 ───────────────────────────────────────────────
Write-Host ""
Write-Host "6. Upload — missing dir field" -ForegroundColor Yellow
try {
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, "missing dir test")
    $srcFile = [System.IO.Path]::ChangeExtension($tmpFile, ".txt")
    Move-Item $tmpFile $srcFile -Force
    Add-Type -AssemblyName System.Net.Http
    $client      = [System.Net.Http.HttpClient]::new()
    $form        = [System.Net.Http.MultipartFormDataContent]::new()
    $fileContent = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($srcFile))
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/plain")
    $form.Add($fileContent, "file", [System.IO.Path]::GetFileName($srcFile))
    $form.Add([System.Net.Http.StringContent]::new($ClaimId), "claimId")
    # intentionally omit "dir"
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Build-UploadUrl))
    $req.Headers.Add("Authorization", "Bearer $token")
    $req.Content = $form
    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    Write-Result "HTTP 400 (missing dir)" ($resp.StatusCode.value__ -eq 400) "Got $($resp.StatusCode.value__)"
    if ($resp.StatusCode.value__ -eq 400) { $passed++ } else { $failed++ }
    Remove-Item $srcFile -ErrorAction SilentlyContinue
    $client.Dispose()
} catch {
    Write-Result "Missing dir check" $false $_.Exception.Message; $failed++
}

# ─── Test 7: Missing file → 400 ──────────────────────────────────────────────
Write-Host ""
Write-Host "7. Upload — missing file field" -ForegroundColor Yellow
try {
    Add-Type -AssemblyName System.Net.Http
    $client = [System.Net.Http.HttpClient]::new()
    $form   = [System.Net.Http.MultipartFormDataContent]::new()
    $form.Add([System.Net.Http.StringContent]::new($Directory), "dir")
    $form.Add([System.Net.Http.StringContent]::new($ClaimId), "claimId")
    # intentionally omit "file"
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Build-UploadUrl))
    $req.Headers.Add("Authorization", "Bearer $token")
    $req.Content = $form
    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
    Write-Result "HTTP 400 (missing file)" ($resp.StatusCode.value__ -eq 400) "Got $($resp.StatusCode.value__)"
    if ($resp.StatusCode.value__ -eq 400) { $passed++ } else { $failed++ }
    $client.Dispose()
} catch {
    Write-Result "Missing file check" $false $_.Exception.Message; $failed++
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────" -ForegroundColor DarkGray
$total = $passed + $failed
Write-Host "Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
if ($failed -gt 0) { exit 1 }
