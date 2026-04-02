CREATE OR ALTER PROCEDURE FacetsEXT..ADT_INSERT_MAILTO
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ATXR_DEST_ID    DATETIME,       -- attachment's ATXR_DEST_ID (becomes ATXR_ATTACH_ID in note)
            @ATXR_SOURCE_ID  DATETIME,       -- claim's ATXR_SOURCE_ID
            @ATSY_ID         VARCHAR(10),    -- attachment's style ID
            @ATDT_DATA       VARCHAR(255),
            @MailToDate      DATE,
            @NoteText        VARCHAR(300),
            @NoteDestId      DATETIME,       -- new ATXR_DEST_ID for the note
            @UsusId          VARCHAR(20) = 'BATCH_SVC',
            @NoteAtsyId      VARCHAR(10) = 'ATN0',
            @Timestamp       VARCHAR(30),
            @RowCount        INT = 0

    -- Ensure sequence row exists for this connection's SPID.
    IF NOT EXISTS (SELECT 1 FROM Facets..CER_SEQS_SEQUENCE WHERE SEQS_SPID = @@SPID % 2000)
    BEGIN
        INSERT INTO Facets..CER_SEQS_SEQUENCE (SEQS_SPID, SEQS_CURRENT_DTM)
        VALUES (@@SPID % 2000, GETDATE())
    END

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT
              ATXR.ATXR_DEST_ID       -- attachment's ATXR_DEST_ID direct from Facets
            , CLCL.ATXR_SOURCE_ID     -- claim's ATXR_SOURCE_ID direct from Facets
            , BLOG.ATSY_ID
            , BLOG.ATDT_DATA
            , BLOG.MailToDate
        FROM FacetsEXT..ATDT_BATCH_LOG BLOG
        JOIN Facets..CMC_CLCL_CLAIM CLCL
            ON CLCL.CLCL_ID = BLOG.CLCL_ID
        JOIN Facets..CER_ATXR_ATTACH_U ATXR
            ON ATXR.ATXR_SOURCE_ID = CLCL.ATXR_SOURCE_ID
        JOIN Facets..CER_ATDT_DATA_D ATDT
            ON ATDT.ATXR_DEST_ID = ATXR.ATXR_DEST_ID
            AND ATDT.ATDT_DATA = BLOG.ATDT_DATA
        WHERE BLOG.StatusMessage    = 'Staged'
          AND BLOG.MailToDate       IS NOT NULL
          AND BLOG.MailToDateLoaded = 0

    OPEN cur
    FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate

    IF @@FETCH_STATUS <> 0
        PRINT 'ADT_INSERT_MAILTO: cursor found 0 rows.'

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @NoteText  = 'MailToDate for ' + @ATDT_DATA + ': ' + CONVERT(VARCHAR(10), @MailToDate, 101)
        SET @Timestamp = CONVERT(VARCHAR(30), GETDATE(), 126)

        PRINT 'Processing: ' + @ATDT_DATA

        -- Generate new ATXR_DEST_ID for the note (same as generateAtxr$ in component).
        SET @NoteDestId = NULL

        UPDATE Facets..CER_SEQS_SEQUENCE
        SET SEQS_CURRENT_DTM = SEQS_CURRENT_DTM
        WHERE SEQS_SPID = @@SPID % 2000

        SELECT @NoteDestId = DATEADD(MILLISECOND, 10, SEQS_CURRENT_DTM)
        FROM Facets..CER_SEQS_SEQUENCE
        WHERE SEQS_SPID = @@SPID % 2000

        IF @NoteDestId IS NULL
        BEGIN
            PRINT 'SKIPPED (no sequence): ' + @ATDT_DATA
            FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate
            CONTINUE
        END

        UPDATE Facets..CER_SEQS_SEQUENCE
        SET SEQS_CURRENT_DTM = @NoteDestId
        WHERE SEQS_SPID = @@SPID % 2000

        BEGIN TRY
            -- addAtxr$: ATXR cross-reference for the note (must exist before ATNT).
            -- ATSY_ID = attachment's style ID (matches component: attachAtsyId ?? noteAtsyId)
            INSERT INTO Facets..CER_ATXR_ATTACH_U (
                ATXR_SOURCE_ID, ATXR_DEST_ID, ATSY_ID, ATTB_ID, ATTB_TYPE,
                ATXR_DESC, ATXR_CREATE_DT, ATXR_CREATE_USUS,
                ATXR_LAST_UPD_DT, ATXR_LAST_UPD_USUS, ATXR_COMPILED_KEY, ATXR_LOCK_TOKEN
            )
            VALUES (
                @ATXR_SOURCE_ID, @NoteDestId, @ATSY_ID, 'CLCL', 'S',
                'Claim Attachment Note', @Timestamp, @UsusId,
                @Timestamp, @UsusId, '', 1
            )

            -- addAtnt$: Note type record. ATXR_ATTACH_ID links note to attachment.
            INSERT INTO Facets..CER_ATNT_NOTE_D (
                ATSY_ID, ATXR_DEST_ID, ATNT_SEQ_NO, ATNT_TYPE, ATXR_ATTACH_ID, ATNT_LOCK_TOKEN
            )
            VALUES (
                @NoteAtsyId, @NoteDestId, 0, 'ATMD', @ATXR_DEST_ID, 1
            )

            -- addAtnd$: Note text. Plain text → VARBINARY same as CERSP_ATND_APPLY.
            INSERT INTO Facets..CER_ATND_NOTE_C (
                ATSY_ID, ATXR_DEST_ID, ATNT_SEQ_NO, ATND_SEQ_NO, ATND_TEXT, ATND_LOCK_TOKEN
            )
            VALUES (
                @NoteAtsyId, @NoteDestId, 0, 0, CONVERT(VARBINARY(MAX), @NoteText), 1
            )

            -- Mark as loaded.
            UPDATE FacetsEXT..ATDT_BATCH_LOG
            SET MailToDateLoaded = 1
            WHERE ATDT_DATA      = @ATDT_DATA
              AND StatusMessage  = 'Staged'

            SET @RowCount = @RowCount + 1
            PRINT 'OK: ' + @ATDT_DATA + ' (MailToDateLoaded=' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ')'

        END TRY
        BEGIN CATCH
            PRINT 'ERROR on ' + @ATDT_DATA + ': ' + ERROR_MESSAGE()
        END CATCH

        FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate
    END

    CLOSE cur
    DEALLOCATE cur

    PRINT 'ADT_INSERT_MAILTO: processed ' + CAST(@RowCount AS VARCHAR(10)) + ' row(s).'
END
