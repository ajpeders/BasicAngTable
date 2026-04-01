-- Add new columns to ATDT_BATCH_LOG for MailToDate and attachment tracking.

ALTER TABLE FacetsEXT..ATDT_BATCH_LOG
    ADD MailToDate       DATE          NULL;

ALTER TABLE FacetsEXT..ATDT_BATCH_LOG
    ADD MailToDateLoaded BIT           NULL DEFAULT 0;

ALTER TABLE FacetsEXT..ATDT_BATCH_LOG
    ADD ATXR_SOURCE_ID   VARCHAR(50)  NULL;
