# claim-attachments.component.ts — Change Log

Issues identified from code review. Listed by priority.

---

## Pending

### Low

- [x] **Dead state fields** (lines 60–66)
  `viewerOpen`, `viewerFilename`, `viewerDirectory`, `viewerIFrameBlobUrl`, `viewerDownloadUrl`, `fileNotes` — confirmed unused in component and template. Removed.

- [x] **`iframeAllowList` vs `iframeAllowListSet` inconsistency** (lines 65, 87)
  The array `['pdf', 'png', ...]` was unused in component and template. Only the Set is used in logic. Array removed.

### Trivial

- [x] **`getData` no-op catch** (lines 731–737)
  `getData` was dead code — never called anywhere. Removed entirely. `spInvokeProm` had the same no-op catch pattern — removed.

- [x] **`buildAuthHeaders` misleading return type** (line 628)
  Typed as `{}` but actually returns an array. Fixed to `{ key: string, value: string }[]`.

- [x] **`noteFormError` init inconsistency** (line 76)
  Initialized as `''` while `attachmentFormError` (same type `string | null`) is initialized as `null`. Fixed to `null`.

- [x] **`console.log` in `ngOnDestroy`** (line 167)
  Debug log left in from development. Removed.

---

## Completed

### UI variants

- **Optional Kendo grid template added**
  Added `claim-attachments.kendo-grid.view.html` as a drop-in alternate view that keeps component logic unchanged.
  Added `KENDO_GRID_VARIANT.md` with exact steps to enable/revert by switching `templateUrl` and importing `GridModule`.

### Logging

- **Misleading log in `refreshSub`** (line 96)
  `LogMessage` fired for every panel event, not just `DeleteMovedLine`. Moved inside the `if` block so it only logs when a reload actually occurs.

- **"Upload started." logged before validation** (line 463)
  Log fired even if the form was invalid and the upload never ran. Moved after the `isAttachmentFormValid` guard.

- **`openFile` error not logged** (line 232)
  File load failures only set `this.view.error` — nothing was sent to `loggingService`. Added `LogMessage` call consistent with other error handlers.

### Medium

- **Subscription leak in `ngOnInit`** (line 109, 125)
  `cfgSub` and `refreshSub` were created inside the `onContextLoaded` subscriber. Fixed by moving `refreshSub` outside, and converting `cfgSub` to `await firstValueFrom(...)`.

- **`pageLoading` flicker** (line 142)
  `finally` block ran before async work completed. Fixed — `pageLoading = false` now lives in `finally` after awaited calls resolve.

- **`pageLoading` not reset on `refreshSub` error**
  If `LoadPageData` threw inside the panel event handler, `pageLoading` stayed `true`. Fixed with try/catch/finally inside the event handler.

### Low

- **Dead `triggerDownload` params** (line 607)
  Method signature accepted `downloadUrl` and `filename` but always read from `this.view`. Confirmed unused in template — params removed.
