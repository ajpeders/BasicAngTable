-- Test: Verify that rows in ATDT_BATCH_LOG can be matched to Facets
-- attachment data (what post-adt checks after the batch loads).
-- Run AFTER pre-adt inserts rows and the ATD batch has run.

-- 1. Check batch log status
SELECT CLCL_ID, ATDT_DATA, ATSY_ID, ATLD_ID, StatusMessage, ErrorMessage, MailToDate, MailToDateLoaded
FROM FacetsEXT..ATDT_BATCH_LOG
WHERE StatusMessage = 'Validated'

-- 2. Check which validated rows actually loaded into Facets (matches post-adt Update-ATDValidation-Post)
SELECT
      BLOG.CLCL_ID
    , BLOG.ATDT_DATA
    , BLOG.StatusMessage
    , Loaded       = CASE WHEN ATDT.ATDT_DATA IS NOT NULL THEN 'Yes' ELSE 'No' END
    , ATXR_DEST    = ATXR.ATXR_DEST_ID
    , ATXR_SOURCE  = ATXR.ATXR_SOURCE_ID
    , HasMailNote  = CASE WHEN ATNT.ATXR_DEST_ID IS NOT NULL THEN 'Yes' ELSE 'No' END
    , BLOG.MailToDate
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
LEFT JOIN Facets..CMC_CLCL_CLAIM CLCL
    ON CLCL.CLCL_ID = BLOG.CLCL_ID
LEFT JOIN Facets..CER_ATXR_ATTACHLU ATXR
    ON ATXR.ATXR_SOURCE_ID = CLCL.ATXR_SOURCE_ID
LEFT JOIN Facets..CER_ATDT_DATA_D ATDT
    ON ATDT.ATXR_DEST_ID = ATXR.ATXR_DEST_ID
    AND ATDT.ATDT_DATA   = BLOG.ATDT_DATA
    AND ATDT.ATLD_ID     = BLOG.ATLD_ID
    AND ATDT.ATSY_ID     = BLOG.ATSY_ID
LEFT JOIN Facets..CER_ATNT_DATA_D ATNT
    ON ATNT.ATXR_DEST_ID = ATDT.ATXR_DEST_ID
    AND ATNT.ATNT_TYPE   = 'ATMD'
WHERE BLOG.StatusMessage = 'Validated'
