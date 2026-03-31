-- Add new columns to ATTD_BATCH_LOG for MailToDate and attachment tracking.

ALTER TABLE FacetsEXT..ATTD_BATCH_LOG
    ADD MailToDate       DATE          NULL;

ALTER TABLE FacetsEXT..ATTD_BATCH_LOG
    ADD MailToDateLoaded BIT           NULL DEFAULT 0;

ALTER TABLE FacetsEXT..ATTD_BATCH_LOG
    ADD ATXR_SOURCE_ID   VARCHAR(50)  NULL;
