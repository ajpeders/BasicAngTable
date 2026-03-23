# Claim Attachments — Local E2E Testing

## Test Environment

| Service | URL | Notes |
|---|---|---|
| Angular App | http://localhost:4200 | `npm start` in `frontend/` |
| Mock Facets Server | http://localhost:3001 | `npm start` in `mock-server/` |
| Azure Function App | http://localhost:7071 | `func start` in `backend/` |
| Azurite (blob) | http://localhost:10000 | Started by mock-server |
| Azurite (file share) | http://localhost:10004 | Started by mock-server |

---

## Test Cases

### 1. Page Load
- [ ] Component renders without errors
- [ ] "Loading attachments..." spinner appears briefly
- [ ] Attachment table populates with seeded test data (1 row: `sample_20240115_103000.txt`)
- [ ] Mail-to date column shows `01/15/2024`
- [ ] Directory description shows `Test Directory`
- [ ] No error banner displayed

### 2. File Download / View
- [x] `.txt` file served with `Content-Disposition: inline` *(verified via curl 2026-03-22)*
- [x] `.docx` file served with `Content-Disposition: attachment` *(verified via curl 2026-03-22)*
- [x] File content correct end-to-end through proxy *(verified via curl 2026-03-22)*
- [ ] Clicking a `.txt` file opens the inline viewer (iframe) — *needs browser test*
- [ ] Non-viewable file type triggers download link — *needs browser test*
- [ ] Close button dismisses the viewer

### 3. File Upload
- [x] Upload through Function App returns `success=true` with timestamped filename *(verified 2026-03-22)*
- [x] Uploaded file written to file share stub and retrievable via GetFile *(verified 2026-03-22)*
- [ ] "Add Attachment" button opens upload form — *needs browser test*
- [ ] Directory dropdown populated — *needs browser test*
- [ ] On success: form closes, attachment table refreshes — *needs browser test*

### 4. Facets Registration SP invoke chain (after upload)
- [x] `CERSP_ATSY_SEARCH_ATTB_ID` — returns ATSY directory list *(verified 2026-03-22)*
- [x] `CERSP_ATTO_SELECT_GEN_IDS` — returns ATXR IDs with COL3 *(verified 2026-03-22)*
- [x] `CERSP_ATDT_APPLY` — returns success *(verified 2026-03-22)*
- [x] `CERSP_ATXR_APPLY` — returns success *(verified 2026-03-22)*
- [x] `CERSP_ATNT_APPLY` — returns success *(verified 2026-03-22)*
- [x] `CERSP_ATND_APPLY` — returns success *(verified 2026-03-22)*
- [x] `CMCSP_CLCL_APPLY` — new-claim path: `ATXR_SOURCE_ID = ATXRDefaultId` triggers `ensureClclAtxrSourceId` → `CERSP_ATTO_SELECT_GEN_IDS` (COL1) → `CMCSP_CLCL_APPLY` with updated `claimData` *(verified via curl 2026-03-22)*

### 5. Note Hover / Add Note
- [ ] Hovering a row with notes shows the note tooltip — *needs browser test*
- [x] `submitNoteForm` SP chain — `CERSP_ATTO_SELECT_GEN_IDS` → `CERSP_ATNT_APPLY` + `CERSP_ATXR_APPLY` + `CERSP_ATND_APPLY` *(verified via curl 2026-03-22)*
- [x] Long note chunking (250 chars → 3 × `CERSP_ATND_APPLY` at seq 0,1,2) *(verified via curl 2026-03-22)*
- [ ] Note tooltip / form UI — *needs browser test*

### 6. Auth / Security (Function App)
- [x] Valid Bearer token + valid claimId → 200 *(verified 2026-03-22)*
- [x] Missing Bearer token → 401 *(verified 2026-03-22)*
- [x] Valid token + unknown claimId → 403 (Facets mock denies access) *(verified 2026-03-22)*
- [x] Directory not found → 404 *(verified 2026-03-22)*
- [x] File not found → 404 *(verified 2026-03-22)*
- [x] Missing `filename` query param → 400 *(verified 2026-03-22)*
- [x] Missing `dir` query param → 400 *(Test-GetFile.ps1 test 7)*
- [x] Missing `claimId` query param → 400 *(Test-GetFile.ps1 test 8)*
- [x] Path traversal filename sanitized → 400 or 404 (never 200/500) *(Test-GetFile.ps1 test 9)*
- [x] Upload missing `dir` field → 400 *(Test-Upload.ps1 test 6)*
- [x] Upload missing `file` field → 400 *(Test-Upload.ps1 test 7)*
- [ ] Function key enforcement — *local func host does not strictly enforce `?code=` locally; enforced by APIM in production*

### 6b. Facets REST API (mock server)
- [x] `GET /RestServices/facets/api/v1/config/browser/:region` — returns `{Data:{region,settings}}` *(verified via curl 2026-03-22)*
- [x] `GET /RestServices/facets/api/v1/claims/:claimId` — known ID → 200 `Access=Granted`; unknown → 403 *(verified via curl 2026-03-22)*
- [x] `GET /RestServices/facets/api/v1/attachments/entities/CLCL` — returns `ATDT_COLL` with seeded file row *(verified via curl 2026-03-22)*
- [x] `CERSP_ATSY_SEARCH_ATTB_ID` — 2 directory rows returned (used by upload form dropdown) *(verified via curl 2026-03-22)*

### 7. APIM Flow
- `Ocp-Apim-Subscription-Key` header is injected by `buildApimHeaders()` in the component when `apimSubscriptionKey` is set
- For local testing: APIM is bypassed; function key (`?code=localkey`) authenticates directly
- For prod/APIM testing: set `LOCAL_APIM_SUB_KEY` in `frontend/src/shims/facets-client-common/index.ts` and change rewrite targets to the APIM base URL
- Production startup code (with `ConfigureFunctionsWebApplication`) is preserved as comments in `backend/Program.cs`

### 8. Error States
- [ ] Upload with no file selected — *needs browser test*
- [ ] Upload over 50 MB — *needs browser test*
- [ ] Mock server down — *needs browser test*

---

## Seed Data

| Item | Value |
|---|---|
| Claim ID | `TEST-CLAIM-001` |
| ATXR Source ID | `2024-01-15T10:30:00` |
| File share | `testshare` |
| Directory | `TESTDIR` |
| Seeded file | `sample_20240115_103000.txt` |
| Function key | `localkey` |
| Mock server port | `3001` |

---

## Results Log

| Date | Tester | Test # | Pass/Fail | Notes |
|---|---|---|---|---|
| 2026-03-22 | auto (curl) | 2,3,4,6 | 12/12 PASS | Backend E2E — download, upload, Facets SP chain, all auth/error paths |
| 2026-03-22 | auto (curl) | 5,6b | 15/15 PASS | Note SP chain (submitNoteForm), long note chunking (3×ATND_APPLY), new-claim CMCSP_CLCL_APPLY, Facets REST endpoints, directory list SP |
| 2026-03-22 | script | 6 | +5 cases added | Missing dir/claimId → 400, path traversal → safe (GetFile); missing dir/file → 400 (Upload) |
