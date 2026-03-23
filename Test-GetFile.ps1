<#
.SYNOPSIS
    Tests the GetFile Azure Function end-to-end against the local environment.

.DESCRIPTION
    Exercises download scenarios against the local Function App (localhost:7071).
    The fake JWT matches what the @facets-client/common shim sends from the Angular app.

.PARAMETER FunctionBaseUrl
    Base URL of the Function App. Defaults to local dev.

.PARAMETER FunctionCode
    Function host key. Defaults to the pre-seeded local dev key.

.PARAMETER ApimSubscriptionKey
    APIM subscription key. Leave empty when hitting the Function App directly
    (bypassing APIM). Required when FunctionBaseUrl points to an APIM endpoint.

.PARAMETER ClaimId
    Claim ID to test against. Must be in the mock server's ACCESSIBLE_CLAIM_IDS set.

.EXAMPLE
    # Local E2E
    .\Test-GetFile.ps1

.EXAMPLE
    # Against a real APIM endpoint
    .\Test-GetFile.ps1 `
        -FunctionBaseUrl "https://your-apim.azure-api.net/facets" `
        -FunctionCode "" `
        -ApimSubscriptionKey "your-sub-key-here" `
        -ClaimId "REAL-CLAIM-ID"
#>
param(
    [string] $FunctionBaseUrl      = "http://localhost:7071/api",
    [string] $FunctionCode         = "localkey",
    [string] $ApimSubscriptionKey  = "",
    [string] $ClaimId              = "TEST-CLAIM-001",
    [string] $Directory            = "TESTDIR",
    [string] $Filename             = "sample_20240115_103000.txt"
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

function Build-Headers([string]$token, [bool]$includeApim = $true) {
    $h = @{ Authorization = "Bearer $token" }
    if ($includeApim -and $ApimSubscriptionKey) {
        $h["Ocp-Apim-Subscription-Key"] = $ApimSubscriptionKey
    }
    return $h
}

function Build-DownloadUrl([string]$file, [string]$dir, [string]$claim) {
    $url = "$FunctionBaseUrl/GetFile?filename=$([Uri]::EscapeDataString($file))&dir=$([Uri]::EscapeDataString($dir))&claimId=$([Uri]::EscapeDataString($claim))"
    if ($FunctionCode) { $url += "&code=$FunctionCode" }
    return $url
}

$token  = New-FakeJwt
$passed = 0
$failed = 0

Write-Host ""
Write-Host "GetFile E2E Tests" -ForegroundColor Cyan
Write-Host "  Base URL : $FunctionBaseUrl"
Write-Host "  ClaimId  : $ClaimId"
Write-Host "  File     : $Directory/$Filename"
Write-Host ""

# ─── Test 1: Successful download ─────────────────────────────────────────────
Write-Host "1. Successful download" -ForegroundColor Yellow
try {
    $url = Build-DownloadUrl $Filename $Directory $ClaimId
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing
    $ok = ($resp.StatusCode -eq 200) -and ($resp.Content.Length -gt 0)
    Write-Result "HTTP 200 with content" $ok "StatusCode=$($resp.StatusCode) Bytes=$($resp.Content.Length)"

    $cd = [string]($resp.Headers["Content-Disposition"] | Select-Object -First 1)
    Write-Result "Content-Disposition: inline (viewable type)" ($cd -like "inline*") "Content-Disposition: $cd"

    $ct = [string]($resp.Headers["Content-Type"] | Select-Object -First 1)
    Write-Result "Content-Type: text/plain" ($ct -like "text/plain*") "Content-Type: $ct"

    if ($ok) { $passed += 3 } else { $failed += 3 }
} catch {
    Write-Result "Download request" $false $_.Exception.Message
    $failed += 3
}

# ─── Test 2: Missing bearer token → 401 ──────────────────────────────────────
Write-Host ""
Write-Host "2. Missing bearer token" -ForegroundColor Yellow
try {
    $url = Build-DownloadUrl $Filename $Directory $ClaimId
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Result "Should have returned 401" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 401 Unauthorized" ($code -eq 401) "Got $code"
    if ($code -eq 401) { $passed++ } else { $failed++ }
}

# ─── Test 3: Unknown claim ID → 403 ──────────────────────────────────────────
Write-Host ""
Write-Host "3. Claim access denied (bad claimId)" -ForegroundColor Yellow
try {
    $url = Build-DownloadUrl $Filename $Directory "BADCLAIM-999"
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing -ErrorAction Stop
    Write-Result "Should have returned 403" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 403 Forbidden" ($code -eq 403) "Got $code"
    if ($code -eq 403) { $passed++ } else { $failed++ }
}

# ─── Test 4: Missing filename param → 400 ────────────────────────────────────
Write-Host ""
Write-Host "4. Missing filename parameter" -ForegroundColor Yellow
try {
    $url = "$FunctionBaseUrl/GetFile?dir=$Directory&claimId=$ClaimId"
    if ($FunctionCode) { $url += "&code=$FunctionCode" }
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing -ErrorAction Stop
    Write-Result "Should have returned 400" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 400 Bad Request" ($code -eq 400) "Got $code"
    if ($code -eq 400) { $passed++ } else { $failed++ }
}

# ─── Test 5: File not found → 404 ────────────────────────────────────────────
Write-Host ""
Write-Host "5. File not found" -ForegroundColor Yellow
try {
    $url = Build-DownloadUrl "doesnotexist_99999999.txt" $Directory $ClaimId
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing -ErrorAction Stop
    Write-Result "Should have returned 404" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 404 Not Found" ($code -eq 404) "Got $code"
    if ($code -eq 404) { $passed++ } else { $failed++ }
}

# ─── Test 6: non-inline type → attachment Content-Disposition ────────────────
Write-Host ""
Write-Host "6. Non-viewable file type served as attachment" -ForegroundColor Yellow
$docxItem = Get-ChildItem "$PSScriptRoot/mock-server/filestore/testshare/$Directory/test_*.docx" -ErrorAction SilentlyContinue | Select-Object -Last 1
$docxFile  = if ($docxItem) { $docxItem.Name } else { $null }
if ($docxFile) {
    try {
        $url = Build-DownloadUrl $docxFile $Directory $ClaimId
        $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing
        $cd = [string]($resp.Headers["Content-Disposition"] | Select-Object -First 1)
        Write-Result "Content-Disposition: attachment (non-viewable type)" ($cd -like "attachment*") "Content-Disposition: $cd"
        if ($cd -like "attachment*") { $passed++ } else { $failed++ }
    } catch {
        Write-Result "Docx download request" $false $_.Exception.Message
        $failed++
    }
} else {
    Write-Host "  [SKIP] No .docx file in file store — run Test-Upload.ps1 first" -ForegroundColor DarkYellow
}

# ─── Test 7: Missing dir param → 400 ─────────────────────────────────────────
Write-Host ""
Write-Host "7. Missing dir parameter" -ForegroundColor Yellow
try {
    $url = "$FunctionBaseUrl/GetFile?filename=$([Uri]::EscapeDataString($Filename))&claimId=$([Uri]::EscapeDataString($ClaimId))"
    if ($FunctionCode) { $url += "&code=$FunctionCode" }
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing -ErrorAction Stop
    Write-Result "Should have returned 400" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 400 Bad Request (missing dir)" ($code -eq 400) "Got $code"
    if ($code -eq 400) { $passed++ } else { $failed++ }
}

# ─── Test 8: Missing claimId param → 400 ─────────────────────────────────────
Write-Host ""
Write-Host "8. Missing claimId parameter" -ForegroundColor Yellow
try {
    $url = "$FunctionBaseUrl/GetFile?filename=$([Uri]::EscapeDataString($Filename))&dir=$([Uri]::EscapeDataString($Directory))"
    if ($FunctionCode) { $url += "&code=$FunctionCode" }
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing -ErrorAction Stop
    Write-Result "Should have returned 400" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 400 Bad Request (missing claimId)" ($code -eq 400) "Got $code"
    if ($code -eq 400) { $passed++ } else { $failed++ }
}

# ─── Test 9: Path traversal attempt → sanitized → 400 or 404 ─────────────────
Write-Host ""
Write-Host "9. Path traversal filename is sanitized (no 500)" -ForegroundColor Yellow
try {
    $traversal = "../../../etc/passwd"
    $url = "$FunctionBaseUrl/GetFile?filename=$([Uri]::EscapeDataString($traversal))&dir=$([Uri]::EscapeDataString($Directory))&claimId=$([Uri]::EscapeDataString($ClaimId))"
    if ($FunctionCode) { $url += "&code=$FunctionCode" }
    $resp = Invoke-WebRequest -Uri $url -Headers (Build-Headers $token) -UseBasicParsing -ErrorAction Stop
    # Should not 200 — if it somehow does, that's a failure
    Write-Result "Should not return 200 for traversal filename" $false "Got $($resp.StatusCode)"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    $safe = $code -in @(400, 404)
    Write-Result "Traversal filename returns 400 or 404 (not 200/500)" $safe "Got $code"
    if ($safe) { $passed++ } else { $failed++ }
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────" -ForegroundColor DarkGray
$total = $passed + $failed
Write-Host "Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
if ($failed -gt 0) { exit 1 }
