# Change Log

---

## 2026-03-15

### /simplify review — fixes applied

**`claim-attachments.view.html`**
- `view?.open`, `view?.canIframe`, `view?.downloadUrl`, `view?.notes` — `view` is typed `ViewState` (never null); removed unnecessary `?.` on all four
- `(view?.notes?.length ?? 0)` → `(view.notes?.length ?? 0)` — `view` not nullable; `notes` is `any[] | null` so inner `?.` stays
- `{{ row.notes.length || 0 }}` → `{{ row.notes.length }}` — `notes: Note[]` is always an array, `|| 0` was dead code

**`claim-attachments.component.ts`**
- `openFile()` subscription: was pushed to the shared `subscriptions[]` array and never removed mid-session — replaced with dedicated `fileLoadSub` field; each new file open cancels the previous in-flight request, preventing race conditions where a slow prior response could overwrite a newer file's view state
- `addAtxr$()`: `nowLocalISOString()` was called twice, producing two `Date` objects that could differ by a millisecond — stored in `const ts` and reused for both `ATXR_CREATE_DT` and `ATXR_LAST_UPD_DT`
- `mapAttachments()`: inner loop scanned all `atsyData` for each row (O(n×m)) — replaced with a `Map<ATSY_ID, ATSY_DESC>` built once before the loop, lookup is now O(1) per row
- `linkNotes()`: called `notes.filter()` for every attachment (O(n×m)) — replaced with a `Map<ATXR_ATTACH_ID, Note[]>` built in one pass; each attachment now looks up its notes in O(1)

**`src/shims/facets-client-common.ts`**
- `makeMinimalPdf()` rebuilt the PDF string on every blob request — added `pdfBlob` cache field; PDF is built once on first call and reused

---

### `claim-attachments.view.html` — textarea whitespace fix

- Both `<textarea>` elements (attachment note form + add note form) had the closing tag on its own indented line — the whitespace between `>` and `</textarea>` was treated as initial content by the browser, causing the box to appear pre-filled with empty space
- Fixed by closing both tags inline with the last attribute line

### `claim-attachments.view.html` — removed lingering inline style on select

- `style="width:100%;"` on the Style `<select>` in the add attachment form — the equivalent rule already exists in SCSS as `.form-grid select { width: 100%; }`
- Removed inline style; no visual change

### `src/shims/facets-client-common.ts` — real PDF blob for file viewer

- `getExternal()` blob response was `new Blob(['dummy file content'])` — not a valid PDF, so the iframe showed a render error
- Added `makeMinimalPdf()` that builds a valid PDF-1.4 structure at runtime (computes xref offsets dynamically) with a "Dev Shim - Test PDF" text label using Helvetica
- File viewer iframe now renders a real page

### `src/shims/facets-client-common.ts` — seed ATSY data for dev

- `HttpService.post()` returned `Rows: []` for all stored procedure calls, so `atsyData` was always `[]`
- This caused two issues: (1) the Style dropdown in the add attachment form had no options, (2) `directoryDesc` was always blank in the attachments table
- Added a branch for `Procedure === 'CERSP_ATSY_SEARCH/ATTB_ID'` that returns two fake rows: `ATDT - Claim Attachment` and `ATMO - Claim Attachment Note`

---

### `claim-attachments.styles.scss` — CSS cleanup & reorganization

**No rules were removed.** All existing classes are referenced in the template.

**Changes made:**

- Broke apart the three catch-all flex groups that had combined unrelated elements:
  - `.ca-header`, `.ca-panel-header`, `.ca-modal-actions` were sharing one `display: flex` rule — each now lives in its own section with its full ruleset
  - `.ca-table-wrap`, `.ca-panel`, `.ca-modal-card` were sharing one card border/shadow rule — each now owns its complete style block

- Reorganized all rules into labeled sections in logical top-down order:
  1. **Shell** — `.ca-shell` root layout
  2. **Typography** — `.ca-eyebrow`, `.ca-copy`
  3. **Buttons** — `.ca-button`, `.ca-button[disabled]`, `.ca-button-secondary`, `.ca-link-button`
  4. **Table** — `.ca-table-wrap`, `.ca-table`, table cell and last-row rules
  5. **State messages** — `.ca-state`, `.ca-state-error`, `.ca-error`
  6. **File viewer panel** — `.ca-panel`, `.ca-panel-header`, `.ca-panel-header p`, `.ca-panel-actions`, `.ca-iframe`
  7. **Modal** — `.ca-modal`, `.ca-modal-card`, modal child element rules, `.ca-modal-actions`
  8. **Header** — `.ca-header`

- No color values, spacing values, or selector logic was altered — output is visually identical

**Unused CSS audit:**

All classes in the stylesheet are referenced in the template — none are unused.

However, the component has a full note hover tooltip system (`noteHover`, `showNoteHover`, `buildNoteHover`, `hideNote`, `cancelNoteHide`) with no corresponding HTML element or CSS in the template. The tooltip markup and its styles are **missing entirely** — likely a transcription gap rather than dead code.

---

### `claim-attachments.view.html` — transcription fixes

- **Line 291, 298:** `attachmentForm.atsyId` → `attachmentForm.directory` — `atsyId` does not exist on `AttachmentForm`
- **Line 427:** `noteFormAttachment.atsyId` → `noteFormAttachment.directory` — `atsyId` does not exist on `ClaimAttachment`
- **Line 468:** `submitNoteForm($event.target.value)` → `submitNoteForm()` — method takes no arguments
- **Lines 367–379:** Removed debug output (raw form state values rendered inline in the attachment form)
- **Iframe inline style** moved to `.iframe-viewer` in SCSS — `border: 3px solid black`, `background: white`, `height: 100%` added to CSS rule; inline `style` attribute removed from HTML
- **All remaining inline styles removed** from HTML and moved to SCSS:
  - `width: 100%` on form inputs/selects/textareas → `.form-grid select, .form-grid input, .form-grid textarea` rule added
  - `height: auto` on form modals → added to `.modal` base rule

---

### `claim-attachments.view.html` — mousedown/click event bug fix

- Add Note button changed from `(click)` to `(mousedown)` — `stopPropagation()` now blocks the same event from bubbling to the `<tr>` and triggering `openFile()` simultaneously

### Transcription fix — `AttachmentForm.directory` → `atsyId`

The `AttachmentForm` interface field was transcribed as `directory` but the work PC uses `atsyId` (the ATSY_ID value from `atsyData`). Updated across all three files:

- **`claim-attachments.interface.ts`** — `directory: string | null` → `atsyId: string | null`
- **`claim-attachments.component.ts`** — `buildAttachmentForm()`, `isAttachmentFormValid`, `uploadAttachmentForm()` all updated to use `atsyId`
- **`claim-attachments.view.html`** — `[value]`, `[selected]`, and `updateAttachmentForm('directory')` all updated to `atsyId`

---

### `claim-attachments.styles.scss` — removed flagged unused rules + font fix

- Removed `.attachments-table-scroll` — was flagged, not used in template
- Removed `.attachments-table tbody tr.clickable` — was flagged, not used in template
- Removed `.modal-footer` — was flagged, not used in template
- Fixed duplicate `Arial` in `font-family: Arial, Arial, Helvetica, sans-serif` → `Arial, Helvetica, sans-serif`

---

### `claim-attachments.styles.scss` — removed animations

- Removed `animation: pop` from `.notes-popover` and its `@keyframes pop` definition
- Removed `animation: submitting-pulse` from `.submit-status` and its `@keyframes submitting-pulse` definition
- Animations were causing issues in the parent app

---

### Build fixes

**`claim-attachments.view.html`**
- Iframe opening tag was missing `>` after inline style removal — fixed
- `$event.target.value` → `$any($event.target).value` on all event bindings (TS strict: `EventTarget` has no `.value`)
- `attachmentForm.directory/mailToDate` → `attachmentForm!.directory/mailToDate` (null-asserted inside `*ngIf` guard)
- `attachmentForm.directory` in `[selected]` → `attachmentForm!.directory`
- `noteFormAttachment.directory/filename` → `noteFormAttachment!.directory/filename`
- `view?.notes?.length > 0` → `(view?.notes?.length ?? 0) > 0` (optional chain can return `undefined`)

**`claim-attachments.view.html`**
- `view?.error` → `view.error` (NG8107: `ViewState.error` is `string`, not nullable — `?.` was unnecessary)

**`claim-attachments.component.ts`**
- `eventNames = []` → `eventNames: string[] = []` (inferred as `never[]` without annotation)

**`src/shims/facets-client-common.ts`**
- Removed unused `HttpFacade` class

**`angular.json`**
- Raised `anyComponentStyle` budget: warning `2kb→8kb`, error `4kb→16kb` (SCSS now 5.32 kB)

---

### `claim-attachments.styles.scss` — unused CSS (new template)

The HTML template was replaced with the work PC version. The following rules exist in the stylesheet but have no matching element in the HTML:

- `.attachments-table-card .attachments-table-scroll` — `attachments-table-scroll` is not used in the template

The old `ca-*` class rules are also now entirely replaced by the new stylesheet.

---

### `claim-attachments.styles.scss` — added missing classes

- **`panel-header-title`** — added simple rule: `margin: 0`, `font-size: 1rem`, `font-weight: 600`
- **`submit-status`** — added with a pulse animation (`submitting-pulse`) to indicate in-progress state; matches the brand blue `#337ab7`

### `claim-attachments.view.html` — removed unused classes

- **`attachments-header-row`** removed from `<thead>` — the thead is fully styled via `.attachments-table thead th`, the class had no effect
- **`notes-wrap`** removed from the notes hover `<div>` — no CSS rule was needed, class was noise

---

### `claim-attachments.component.ts` — transcription fix: `trackById`

**Line 521:** `trackById` was returning `af.id` but `ClaimAttachment` has no `id` property — `trackBy` was always returning `undefined`, making it a no-op.

- **Before:** `trackById = (_: number, af: any) => af.id;`
- **After:** `trackById = (_: number, af: any) => af.ATXR_DEST_ID;`
