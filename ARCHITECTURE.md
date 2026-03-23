# Claim Attachments — Architecture & Flow

## Overview

This project is a full-stack claim attachment management system for the Facets insurance platform. It is structured as three independently runnable services plus an Angular library that gets embedded in the Facets host shell.

```
┌─────────────────────────────────────────────────────────────────┐
│  Browser                                                        │
│                                                                 │
│  Angular App (localhost:4200)                                   │
│  └── claim-attachments library component                        │
│        │  HTTP via /api proxy                                   │
└────────┼────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Azure Function App (localhost:7071)                            │
│  ├── POST /api/upload       ← PostFileFunction.cs               │
│  └── GET  /api/GetFile      ← GetFileFunction.cs                │
│        │                         │                             │
│        │  ValidateClaimAccess    │  ValidateClaimAccess         │
│        ▼                         ▼                             │
│  ┌─────────────────┐    ┌──────────────────────────┐           │
│  │ FacetsService   │    │  FileShareService         │           │
│  │ (REST calls to  │    │  (Azure File Share SDK)   │           │
│  │  mock server)   │    │  ── stub: port 10004 ──   │           │
│  └────────┬────────┘    └──────────────────────────┘           │
└───────────┼─────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Mock Server (localhost:3001 / 10004)                           │
│  ├── Express :3001  — Facets REST API stub                      │
│  │     ├── GET  /RestServices/facets/api/v1/config/browser/:r   │
│  │     ├── GET  /RestServices/facets/api/v1/claims/:claimId     │
│  │     ├── GET  /RestServices/facets/api/v1/attachments/...     │
│  │     └── POST /data/procedure/execute   (SP invoke)           │
│  └── Express :10004 — Azure File Share REST stub                │
│        └── Local filesystem: mock-server/filestore/             │
└─────────────────────────────────────────────────────────────────┘
```

In production, the mock server is replaced by the real Facets REST API and Azure File Share. The Function App can sit behind APIM.

---

## Starting the Local Stack

Start each service in a separate terminal, in this order:

```bash
# 1. Mock Facets server + file share stub (must be up before Function App)
cd mock-server
npm install      # first time only
npm start        # starts Express :3001 and File Share stub :10004

# 2. Azure Function App (.NET 8)
cd backend
func start       # listens on :7071

# 3. Angular dev server
cd frontend
npm install      # first time only
npm start        # ng serve :4200, proxies /api → :7071
```

Open http://localhost:4200. The app loads with seed data for claim `TEST-CLAIM-001`.

---

## Service Responsibilities

### Angular app (`frontend/`)

The `claim-attachments` library component (`projects/claim-attachments/src/lib/`) handles all UI:
- Loads attachment list on init via the Facets REST API (through the Facets SDK shim)
- Renders the attachment table, inline viewer, upload form, and note editor
- After a successful upload, runs the Facets SP registration chain directly against the mock server

The test harness app (`src/app/`) embeds the library and injects context (claim ID, tokens) via the `facets-client-common` shim in `src/shims/`.

### Azure Function App (`backend/`)

Two HTTP-triggered functions. Both share the same auth flow:

1. Extract Bearer JWT from `Authorization` header
2. Call `FacetsService.ValidateClaimAccessAsync` → `GET /claims/:claimId` on mock server
3. Proceed to file operation (Azure File Share SDK) or return 401/403/400

`PostFileFunction` — `POST /api/upload` (multipart form):
- Fields: `file`, `dir`, `claimId`
- Timestamps the filename: `{name}_{yyyyMMdd_HHmmss}{ext}`
- Writes to Azure File Share (or local stub via port 10004)

`GetFileFunction` — `GET /api/GetFile`:
- Params: `filename`, `dir`, `claimId`
- Sets `Content-Disposition: inline` for viewable types (txt, pdf, images, etc.)
- Sets `Content-Disposition: attachment` for all others

### Mock server (`mock-server/server.js`)

Two Express instances:

**Port 3001 — Facets REST API**

| Endpoint | Purpose |
|---|---|
| `GET /RestServices/facets/api/v1/config/browser/:region` | Returns region config (called on component init) |
| `GET /RestServices/facets/api/v1/claims/:claimId` | Access check — returns `Access: Granted` or 403 |
| `GET /RestServices/facets/api/v1/attachments/entities/CLCL` | Returns attachment list for a claim |
| `POST /data/procedure/execute` | SP invoke — dispatches to named stored procedure handlers |

**Port 10004 — Azure File Share stub**

Mirrors the Azure File Share REST API surface against the local `filestore/` directory. The Function App's `FileShareService` uses the standard Azure SDK, which points at this port via `local.settings.json`.

---

## Request Flows

### Download flow

```
Browser clicks file row
  → component builds URL: GET /api/GetFile?filename=...&dir=...&claimId=...
  → Angular HTTP client (with Bearer token) → Function App :7071
      → parse JWT claims (ususid, region, appid)
      → GET :3001/claims/:claimId  → Access=Granted
      → Azure File Share SDK → GET :10004/account/testshare/TESTDIR/:filename
      → stream file bytes back with Content-Type + Content-Disposition headers
  → component opens blob URL in iframe (inline) or triggers download link
```

### Upload flow

```
User fills upload form (file + directory + optional note) → submits
  → component POST /api/upload (multipart: file, dir, claimId, Bearer token)
  → Function App :7071
      → parse JWT
      → GET :3001/claims/:claimId  → Access=Granted
      → validate file size (≤ 50 MB default)
      → check directory exists on file share
      → write file as {name}_{timestamp}{ext}
      → return { success: true, filename: "..." }
  → component receives filename, then runs Facets SP registration chain:
      1. CERSP_ATSY_SEARCH_ATTB_ID       → directory metadata
      2. CERSP_ATTO_SELECT_GEN_IDS       → generate ATXR_DEST_ID (COL3)
         [if new claim: also COL1 → CMCSP_CLCL_APPLY to stamp ATXR_SOURCE_ID]
      3. CERSP_ATDT_APPLY                → register attachment data record
      4. CERSP_ATXR_APPLY                → register cross-reference
      5. CERSP_ATNT_APPLY                → register note type (if note present)
      6. CERSP_ATND_APPLY × N            → register note text in 250-char chunks
  → attachment table refreshes
```

### Note submission flow

```
User adds note to existing attachment → submits
  → component runs note SP chain directly against Facets REST:
      1. CERSP_ATTO_SELECT_GEN_IDS       → generate ATXR_DEST_ID for the note
      2. CERSP_ATNT_APPLY                → note type header
      3. CERSP_ATXR_APPLY                → cross-reference
      4. CERSP_ATND_APPLY × N            → note text chunks (250-char each, seq 0,1,2…)
```

---

## Authentication Model

### Local dev
- Angular shim (`src/shims/facets-client-common/index.ts`) generates a fake JWT with hardcoded claims: `facets-ususid`, `facets-region`, `facets-appid`
- Function App accepts any Bearer token locally (no signature verification — mock Facets access check is the only gate)
- Function key is `localkey` (set in `local.settings.json`)

### Production (APIM path)
- Real Facets JWT issued by the identity provider
- APIM validates `Ocp-Apim-Subscription-Key` and forwards to the Function App
- Function App reads JWT claims for user identity and calls the real Facets REST API
- Startup code for APIM/AspNetCore mode is preserved as comments in `backend/Program.cs`

---

## File Naming & Storage

- Uploaded files are stored as `{originalName}_{yyyyMMdd_HHmmss}{ext}` to avoid collisions
- Filenames and directory names are sanitized by `FileShareServiceHelpers.SanitizeName`:
  - Strips invalid filesystem characters and `/`, `\`
  - Removes `..` sequences (path traversal prevention)
  - Truncates to 255 characters (Azure File Share limit)
- Viewable inline extensions: `.pdf`, `.txt`, `.json`, `.xml`, `.csv`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.webp`, `.mp3`, `.wav`, `.ogg`
- All others served as `attachment` (download)

---

## Key Files

| File | Purpose |
|---|---|
| `backend/Functions/GetFileFunction.cs` | Download endpoint |
| `backend/Functions/PostFileFunction.cs` | Upload endpoint |
| `backend/Services/FileShareService.cs` | Azure File Share client wrapper |
| `backend/Services/FacetsService.cs` | Facets REST claim validation |
| `backend/Services/FileShareServiceHelpers.cs` | MIME types, sanitization, inline check |
| `frontend/projects/claim-attachments/src/lib/claim-attachments.component.ts` | Main UI component (848 lines) |
| `frontend/projects/claim-attachments/src/lib/claim-attachments.service.ts` | HTTP wrapper for upload/download |
| `frontend/projects/claim-attachments/src/lib/claim-attachments.interface.ts` | TypeScript data models |
| `frontend/src/shims/facets-client-common/index.ts` | Facets SDK shim (injects auth context locally) |
| `mock-server/server.js` | Facets REST + File Share stubs |
| `mock-server/filestore/` | Local file storage for the stub |
| `E2E_TESTING.md` | Test cases, results log, seed data |
| `Test-GetFile.ps1` | PowerShell E2E tests for download |
| `Test-Upload.ps1` | PowerShell E2E tests for upload + SP chain |
| `Test-All.ps1` | PowerShell E2E tests for SP invoke paths |

---

## Seed Data

| Item | Value |
|---|---|
| Claim ID | `TEST-CLAIM-001` |
| ATXR Source ID | `2024-01-15T10:30:00` |
| ATXR Default (sentinel) | `1753-01-01T00:00:00` |
| File share | `testshare` |
| Directory | `TESTDIR` |
| Seeded file | `sample_20240115_103000.txt` |
| Function key | `localkey` |
| Mock server port | `3001` |
| File share stub port | `10004` |
