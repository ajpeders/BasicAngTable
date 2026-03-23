<#
.SYNOPSIS
    Comprehensive E2E tests for all SP invoke paths and Facets API endpoints.

.DESCRIPTION
    Covers the remaining untested paths not exercised by Test-GetFile.ps1 and
    Test-Upload.ps1:
      - Note submission SP chain (submitNoteForm flow)
      - New-claim path: ATXR_SOURCE_ID = ATXRDefaultId → CMCSP_CLCL_APPLY
      - Long note chunking (>100 chars → multiple CERSP_ATND_APPLY calls)
      - Facets config browser endpoint
      - Attachment list REST endpoint
      - CERSP_ATSY_SEARCH_ATTB_ID (directory list for upload form dropdown)

.PARAMETER MockFacetsBaseUrl
    Base URL of the mock Facets server.

.PARAMETER ClaimId
    Claim ID in the mock server's ACCESSIBLE_CLAIM_IDS set.

.PARAMETER AtxrSourceId
    Existing ATXR_SOURCE_ID for note submission tests (seed data default).

.PARAMETER AtxrDefaultId
    The sentinel default value the component uses for "no ATXR yet".

.EXAMPLE
    # All services running
    .\Test-All.ps1

.EXAMPLE
    # Custom base URL
    .\Test-All.ps1 -MockFacetsBaseUrl "http://localhost:3001"
#>
param(
    [string] $MockFacetsBaseUrl = "http://localhost:3001",
    [string] $ClaimId          = "TEST-CLAIM-001",
    [string] $AtxrSourceId     = "2024-01-15T10:30:00",
    [string] $AtxrDefaultId    = "1753-01-01T00:00:00",
    [string] $Region           = "LOCAL"
)

# ─── Helpers ──────────────────────────────────────────────────────────────────

function Coalesce($a, $b) { if ($null -ne $a -and $a -ne '') { $a } else { $b } }

function Write-Result([string]$label, [bool]$pass, [string]$detail = "") {
    $status = if ($pass) { "PASS" } else { "FAIL" }
    $color  = if ($pass) { "Green" } else { "Red" }
    Write-Host "  [$status] $label" -ForegroundColor $color
    if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
}

function Invoke-SpInvoke([string]$procedure, [hashtable]$parameters = @{}) {
    $body = @{
        Procedure  = $procedure
        Parameters = $parameters
        Analyze    = $false
        Identity   = "SVCAGENT"
    } | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Uri "$MockFacetsBaseUrl/data/procedure/execute" `
        -Method Post -ContentType "application/json" -Body $body
}

$passed = 0
$failed = 0

Write-Host ""
Write-Host "Comprehensive SP Invoke + Facets API E2E Tests" -ForegroundColor Cyan
Write-Host "  Facets mock : $MockFacetsBaseUrl"
Write-Host "  ClaimId     : $ClaimId"
Write-Host "  ATXR src    : $AtxrSourceId"
Write-Host ""

# ─── Section 1: Facets REST endpoints ─────────────────────────────────────────
Write-Host "── 1. Facets REST API endpoints ──────────────────────────────────" -ForegroundColor Yellow

# 1a. Config browser endpoint (called by component on context load)
Write-Host ""
Write-Host "1a. GET config/browser/:region" -ForegroundColor Yellow
try {
    $url  = "$MockFacetsBaseUrl/RestServices/facets/api/v1/config/browser/$Region"
    $resp = Invoke-RestMethod -Uri $url -Method Get
    $ok   = $null -ne $resp.Data
    Write-Result "200 with Data field" $ok "Data=$($resp.Data | ConvertTo-Json -Compress)"
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "Config endpoint reachable" $false $_.Exception.Message; $failed++
}

# 1b. Claim access check — granted
Write-Host ""
Write-Host "1b. GET claims/:claimId — known claim (granted)" -ForegroundColor Yellow
try {
    $url  = "$MockFacetsBaseUrl/RestServices/facets/api/v1/claims/$ClaimId"
    $resp = Invoke-RestMethod -Uri $url -Method Get
    $ok   = $resp.Data.Access -eq "Granted"
    Write-Result "Access=Granted" $ok "Access=$($resp.Data.Access)"
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "Claim access granted" $false $_.Exception.Message; $failed++
}

# 1c. Claim access check — denied (unknown claim)
Write-Host ""
Write-Host "1c. GET claims/:claimId — unknown claim (denied → 403)" -ForegroundColor Yellow
try {
    $url = "$MockFacetsBaseUrl/RestServices/facets/api/v1/claims/BADCLAIM-999"
    Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    Write-Result "Should have returned 403" $false "Got 200"
    $failed++
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Result "HTTP 403 for unknown claim" ($code -eq 403) "Got $code"
    if ($code -eq 403) { $passed++ } else { $failed++ }
}

# 1d. Attachment list REST endpoint
Write-Host ""
Write-Host "1d. GET attachments/entities/CLCL" -ForegroundColor Yellow
try {
    $url  = "$MockFacetsBaseUrl/RestServices/facets/api/v1/attachments/entities/CLCL?ATXR_SOURCE_ID=$([Uri]::EscapeDataString($AtxrSourceId))"
    $resp = Invoke-RestMethod -Uri $url -Method Get
    $rows = $resp.Data.Attachments.ATDT_COLL
    $ok   = $rows.Count -gt 0
    Write-Result "Returns at least one attachment row" $ok "Rows=$($rows.Count)"
    if ($ok) {
        $row = $rows[0]
        Write-Result "  ATDT_DATA matches seeded filename" ($row.ATDT_DATA -like "*.txt") "ATDT_DATA=$($row.ATDT_DATA)"
        Write-Result "  ATXR_SOURCE_ID present" (![string]::IsNullOrEmpty($row.ATXR_SOURCE_ID)) "ATXR_SOURCE_ID=$($row.ATXR_SOURCE_ID)"
        $passed += 3
    } else {
        $failed += 3
    }
} catch {
    Write-Result "Attachment list endpoint reachable" $false $_.Exception.Message; $failed += 3
}

# ─── Section 2: SP invoke — directory list (upload form dropdown) ──────────────
Write-Host ""
Write-Host "── 2. SP invoke — CERSP_ATSY_SEARCH_ATTB_ID (directory dropdown) ─" -ForegroundColor Yellow

try {
    $r    = Invoke-SpInvoke "CERSP_ATSY_SEARCH_ATTB_ID"
    $rows = $r.Data.ResultSets[0].Rows
    $ok   = $rows.Count -ge 1
    Write-Result "Returns directory rows" $ok "Count=$($rows.Count)"
    if ($ok) {
        Write-Result "  First row has ATSY_ID + ATSY_DESC" (![string]::IsNullOrEmpty($rows[0].ATSY_ID) -and ![string]::IsNullOrEmpty($rows[0].ATSY_DESC)) `
            "ATSY_ID=$($rows[0].ATSY_ID) ATSY_DESC=$($rows[0].ATSY_DESC)"
        $passed += 2
    } else {
        $failed += 2
    }
} catch {
    Write-Result "CERSP_ATSY_SEARCH_ATTB_ID" $false $_.Exception.Message; $failed += 2
}

# ─── Section 3: Note submission SP chain ──────────────────────────────────────
Write-Host ""
Write-Host "── 3. Note submission SP invoke chain (submitNoteForm flow) ──────" -ForegroundColor Yellow

# Step 1: generate ATXR IDs for the note
Write-Host ""
Write-Host "3a. CERSP_ATTO_SELECT_GEN_IDS — generate note ATXR IDs" -ForegroundColor Yellow
$noteAtxrDest = $null
try {
    $r = Invoke-SpInvoke "CERSP_ATTO_SELECT_GEN_IDS" @{
        ATXR_SOURCE_ID = $AtxrSourceId
        ATSY_ID        = "ATDT"
        ATXR_DEST_ID   = $AtxrDefaultId
    }
    $noteAtxrDest = $r.Data.ResultSets[0].Rows[0].COL3
    $ok = ![string]::IsNullOrEmpty($noteAtxrDest)
    Write-Result "Got COL3 (ATXR_DEST_ID for note)" $ok "ATXR_DEST_ID=$noteAtxrDest"
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATTO_SELECT_GEN_IDS (note)" $false $_.Exception.Message; $failed++
}

# Step 2: CERSP_ATNT_APPLY — note header
Write-Host ""
Write-Host "3b. CERSP_ATNT_APPLY — add note type record" -ForegroundColor Yellow
try {
    $r  = Invoke-SpInvoke "CERSP_ATNT_APPLY" @{
        ATXR_DEST_ID   = Coalesce $noteAtxrDest "gen-dest-001"
        ATXR_ATTACH_ID = "dest-001"
        ATNT_TYPE      = ""
        ATSY_ID        = "ATDT"
    }
    $ok = $null -ne $r.Data.ResultSets
    Write-Result "CERSP_ATNT_APPLY returns ResultSets" $ok
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATNT_APPLY" $false $_.Exception.Message; $failed++
}

# Step 3: CERSP_ATXR_APPLY — note cross-reference record
Write-Host ""
Write-Host "3c. CERSP_ATXR_APPLY — add note cross-reference" -ForegroundColor Yellow
try {
    $r  = Invoke-SpInvoke "CERSP_ATXR_APPLY" @{
        ATXR_SOURCE_ID = $AtxrSourceId
        ATXR_DEST_ID   = Coalesce $noteAtxrDest "gen-dest-001"
        ATSY_ID        = "ATDT"
        ATXR_DESC      = "Claim Attachment Note"
        USUS_ID        = "TESTUSER"
    }
    $ok = $null -ne $r.Data.ResultSets
    Write-Result "CERSP_ATXR_APPLY returns ResultSets" $ok
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATXR_APPLY" $false $_.Exception.Message; $failed++
}

# Step 4: CERSP_ATND_APPLY — single short note (≤100 chars, 1 call)
Write-Host ""
Write-Host "3d. CERSP_ATND_APPLY — short note text (single chunk)" -ForegroundColor Yellow
try {
    $r  = Invoke-SpInvoke "CERSP_ATND_APPLY" @{
        ATSY_ID      = "ATDT"
        ATXR_DEST_ID = Coalesce $noteAtxrDest "gen-dest-001"
        ATNT_SEQ_NO  = 0
        ATND_SEQ_NO  = 0
        ATND_TEXT    = "Short test note."
    }
    $ok = $null -ne $r.Data.ResultSets
    Write-Result "CERSP_ATND_APPLY (chunk 0) returns ResultSets" $ok
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATND_APPLY (single chunk)" $false $_.Exception.Message; $failed++
}

# ─── Section 4: Long note chunking (>100 chars → multiple CERSP_ATND_APPLY) ───
Write-Host ""
Write-Host "── 4. Long note chunking (>100 chars → multiple CERSP_ATND_APPLY) ─" -ForegroundColor Yellow

$longNote = "A" * 250   # 250 chars → 3 chunks of 100, 100, 50
$chunks   = @()
for ($i = 0; $i -lt $longNote.Length; $i += 100) {
    $end = [Math]::Min($i + 100, $longNote.Length)
    $chunks += $longNote.Substring($i, $end - $i)
}
Write-Host "  Note length=$($longNote.Length) → $($chunks.Count) chunks" -ForegroundColor DarkGray

$chunksPassed = 0
for ($idx = 0; $idx -lt $chunks.Count; $idx++) {
    try {
        $r  = Invoke-SpInvoke "CERSP_ATND_APPLY" @{
            ATSY_ID      = "ATDT"
            ATXR_DEST_ID = Coalesce $noteAtxrDest "gen-dest-001"
            ATNT_SEQ_NO  = 0
            ATND_SEQ_NO  = $idx
            ATND_TEXT    = $chunks[$idx]
        }
        $ok = $null -ne $r.Data.ResultSets
        Write-Result "  CERSP_ATND_APPLY chunk $idx (len=$($chunks[$idx].Length))" $ok
        if ($ok) { $chunksPassed++; $passed++ } else { $failed++ }
    } catch {
        Write-Result "  CERSP_ATND_APPLY chunk $idx" $false $_.Exception.Message; $failed++
    }
}
Write-Result "All $($chunks.Count) chunks sent successfully" ($chunksPassed -eq $chunks.Count) "$chunksPassed/$($chunks.Count) passed"
if ($chunksPassed -eq $chunks.Count) { $passed++ } else { $failed++ }

# ─── Section 5: New-claim path — CMCSP_CLCL_APPLY ────────────────────────────
Write-Host ""
Write-Host "── 5. New-claim path (ATXR_SOURCE_ID = default → CMCSP_CLCL_APPLY) ─" -ForegroundColor Yellow

# Step 1: generate new ATXR_SOURCE_ID for the claim (uses COL1 not COL3)
Write-Host ""
Write-Host "5a. CERSP_ATTO_SELECT_GEN_IDS for new claim (ATXR_SOURCE_ID = default)" -ForegroundColor Yellow
$newClaimAtxrSrc = $null
try {
    $r = Invoke-SpInvoke "CERSP_ATTO_SELECT_GEN_IDS" @{
        ATXR_SOURCE_ID = $AtxrDefaultId
        ATSY_ID        = "ATDT"
        ATXR_DEST_ID   = $AtxrDefaultId
    }
    $newClaimAtxrSrc = $r.Data.ResultSets[0].Rows[0].COL1
    $ok = ![string]::IsNullOrEmpty($newClaimAtxrSrc)
    Write-Result "Got COL1 (new ATXR_SOURCE_ID for claim)" $ok "COL1=$newClaimAtxrSrc"
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATTO_SELECT_GEN_IDS (new claim)" $false $_.Exception.Message; $failed++
}

# Step 2: CMCSP_CLCL_APPLY — update claim with new ATXR_SOURCE_ID
Write-Host ""
Write-Host "5b. CMCSP_CLCL_APPLY — stamp new ATXR_SOURCE_ID onto claim" -ForegroundColor Yellow
try {
    $clclData = @{
        CLCL_ID        = $ClaimId
        ATXR_SOURCE_ID = Coalesce $newClaimAtxrSrc "gen-src-001"
        CLCL_STATUS    = "O"
    }
    $r  = Invoke-SpInvoke "CMCSP_CLCL_APPLY" $clclData
    $ok = $null -ne $r.Data.ResultSets
    Write-Result "CMCSP_CLCL_APPLY returns ResultSets" $ok "ATXR_SOURCE_ID used=$(Coalesce $newClaimAtxrSrc 'gen-src-001')"
    if ($ok) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CMCSP_CLCL_APPLY" $false $_.Exception.Message; $failed++
}

# ─── Section 6: Upload registration chain (ATDT + ATXR + ATNT + ATND) ─────────
Write-Host ""
Write-Host "── 6. Full upload registration chain (CERSP_ATDT/ATXR/ATNT/ATND_APPLY) ─" -ForegroundColor Yellow

# generate dest ID for a new attachment record
$uploadAtxrDest = $null
try {
    $r = Invoke-SpInvoke "CERSP_ATTO_SELECT_GEN_IDS" @{
        ATXR_SOURCE_ID = $AtxrSourceId
        ATSY_ID        = "ATDT"
        ATXR_DEST_ID   = $AtxrDefaultId
    }
    $uploadAtxrDest = $r.Data.ResultSets[0].Rows[0].COL3
    Write-Result "CERSP_ATTO_SELECT_GEN_IDS (upload reg)" (![string]::IsNullOrEmpty($uploadAtxrDest)) "ATXR_DEST_ID=$uploadAtxrDest"
    if (![string]::IsNullOrEmpty($uploadAtxrDest)) { $passed++ } else { $failed++ }
} catch {
    Write-Result "CERSP_ATTO_SELECT_GEN_IDS (upload)" $false $_.Exception.Message; $failed++
}

foreach ($proc in @("CERSP_ATDT_APPLY", "CERSP_ATXR_APPLY", "CERSP_ATNT_APPLY", "CERSP_ATND_APPLY")) {
    try {
        $r  = Invoke-SpInvoke $proc
        $ok = $null -ne $r.Data.ResultSets
        Write-Result "$proc" $ok
        if ($ok) { $passed++ } else { $failed++ }
    } catch {
        Write-Result "$proc" $false $_.Exception.Message; $failed++
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────" -ForegroundColor DarkGray
$total = $passed + $failed
Write-Host "Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
if ($failed -gt 0) { exit 1 }
