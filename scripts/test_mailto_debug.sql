-- Run in SSMS after pre-adt + batch/spoof, BEFORE post-adt.
-- Shows exactly what the proc does and whether notes land in Facets.

-- 1. Show what the cursor will find.
PRINT '=== CURSOR INPUT ==='
SELECT ATDT_DATA, ATXR_DEST_ID, ATXR_SOURCE_ID, ATSY_ID, MailToDate, MailToDateLoaded
FROM FacetsEXT..ATDT_BATCH_LOG
WHERE StatusMessage = 'Staged'
  AND MailToDate IS NOT NULL
  AND MailToDateLoaded = 0
  AND ATXR_DEST_ID IS NOT NULL
  AND ATXR_SOURCE_ID IS NOT NULL

-- 2. Run the proc.
PRINT ''
PRINT '=== RUNNING PROC ==='
EXEC FacetsEXT..ADT_INSERT_MAILTO

-- 3. Check if notes actually exist in Facets.
PRINT ''
PRINT '=== VERIFY NOTES IN FACETS ==='
SELECT
    BLOG.ATDT_DATA,
    BLOG.MailToDateLoaded,
    NoteATNT    = ATNT.ATXR_DEST_ID,
    NoteATXR    = NOTEXR.ATXR_DEST_ID,
    NoteATND    = ATND.ATXR_DEST_ID,
    AttachLink  = ATNT.ATXR_ATTACH_ID,
    BlogDest    = BLOG.ATXR_DEST_ID
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
LEFT JOIN Facets..CER_ATNT_NOTE_D ATNT
    ON ATNT.ATXR_ATTACH_ID = BLOG.ATXR_DEST_ID
    AND ATNT.ATNT_TYPE = 'ATMD'
LEFT JOIN Facets..CER_ATXR_ATTACH_U NOTEXR
    ON NOTEXR.ATXR_DEST_ID = ATNT.ATXR_DEST_ID
LEFT JOIN Facets..CER_ATND_NOTE_C ATND
    ON ATND.ATXR_DEST_ID = ATNT.ATXR_DEST_ID
WHERE BLOG.StatusMessage IN ('Staged', 'Loaded', 'Complete')
  AND BLOG.MailToDate IS NOT NULL
