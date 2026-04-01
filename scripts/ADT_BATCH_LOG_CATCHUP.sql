CREATE OR ALTER PROCEDURE FacetsEXT..ADT_BATCH_LOG_CATCHUP
AS
BEGIN
    SET NOCOUNT ON;

    -- Finds any rows that have a MailToDate but never got the note inserted,
    -- regardless of status. Resets them to 'Staged' so ADT_INSERT_MAILTO can
    -- pick them up on the next run.
    UPDATE FacetsEXT..ATDT_BATCH_LOG
    SET StatusMessage    = 'Staged',
        MailToDateLoaded = 0
    WHERE MailToDate       IS NOT NULL
      AND MailToDateLoaded = 0
      AND ATXR_DEST_ID     IS NOT NULL
      AND ATXR_SOURCE_ID   IS NOT NULL
      AND StatusMessage    <> 'Staged'
END
