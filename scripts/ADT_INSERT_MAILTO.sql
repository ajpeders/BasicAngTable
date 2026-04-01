CREATE OR ALTER PROCEDURE FacetsEXT..ADT_INSERT_MAILTO
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ATXR_DEST_ID    DATETIME,
            @ATXR_SOURCE_ID  DATETIME,
            @ATSY_ID         VARCHAR(10),
            @ATDT_DATA       VARCHAR(255),
            @MailToDate      DATE,
            @NoteText        VARCHAR(300),
            @NoteDestId      DATETIME,
            @UsusId          VARCHAR(20) = 'BATCH_SVC',
            @NoteAtsyId      VARCHAR(10) = 'ATMO',
            @Timestamp       VARCHAR(30),
            @RowCount        INT = 0,
            @UpdateCount     INT = 0

    -- Ensure sequence row exists for this connection's SPID.
    IF NOT EXISTS (SELECT 1 FROM Facets..CER_SEQS_SEQUENCE WHERE SEQS_SPID = @@SPID % 2000)
    BEGIN
        INSERT INTO Facets..CER_SEQS_SEQUENCE (SEQS_SPID, SEQS_CURRENT_DTM)
        VALUES (@@SPID % 2000, GETDATE())
    END

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT
              ATXR_DEST_ID
            , ATXR_SOURCE_ID
            , ATSY_ID
            , ATDT_DATA
            , MailToDate
        FROM FacetsEXT..ATDT_BATCH_LOG
        WHERE StatusMessage    = 'Staged'
          AND MailToDate       IS NOT NULL
          AND MailToDateLoaded = 0
          AND ATXR_DEST_ID     IS NOT NULL
          AND ATXR_SOURCE_ID   IS NOT NULL

    OPEN cur
    FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate

    IF @@FETCH_STATUS <> 0
        PRINT 'ADT_INSERT_MAILTO: cursor found 0 rows.'

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @NoteText  = 'MailToDate for ' + @ATDT_DATA + ': ' + CONVERT(VARCHAR(10), @MailToDate, 101)
        SET @Timestamp = CONVERT(VARCHAR(30), GETDATE(), 126)

        PRINT 'Processing: ' + @ATDT_DATA + ' | ATXR_DEST=' + CONVERT(VARCHAR(30), @ATXR_DEST_ID, 126) + ' | ATXR_SRC=' + CONVERT(VARCHAR(30), @ATXR_SOURCE_ID, 126)

        -- Generate new ATXR_DEST_ID from sequence table.
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

        -- Step 1: Insert ATNT note type record.
        INSERT INTO Facets..CER_ATNT_NOTE_D (
            ATSY_ID, ATXR_DEST_ID, ATNT_SEQ_NO, ATNT_TYPE, ATXR_ATTACH_ID, ATNT_LOCK_TOKEN
        )
        VALUES (
            @NoteAtsyId, @NoteDestId, 0, 'ATMD', @ATXR_DEST_ID, 1
        )

        -- Step 2: Insert ATXR cross-reference for the note.
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

        -- Step 3: Insert ATND note text.
        INSERT INTO Facets..CER_ATND_NOTE_C (
            ATSY_ID, ATXR_DEST_ID, ATNT_SEQ_NO, ATND_SEQ_NO, ATND_TEXT, ATND_LOCK_TOKEN
        )
        VALUES (
            @NoteAtsyId, @NoteDestId, 0, 0, CONVERT(VARBINARY(MAX), @NoteText), 1
        )

        -- Mark as loaded.
        UPDATE FacetsEXT..ATDT_BATCH_LOG
        SET MailToDateLoaded = 1
        WHERE ATXR_DEST_ID = @ATXR_DEST_ID
          AND ATDT_DATA    = @ATDT_DATA

        SET @UpdateCount = @@ROWCOUNT
        PRINT 'MailToDateLoaded UPDATE matched ' + CAST(@UpdateCount AS VARCHAR(10)) + ' row(s) for: ' + @ATDT_DATA

        SET @RowCount = @RowCount + 1

        FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate
    END

    CLOSE cur
    DEALLOCATE cur

    PRINT 'ADT_INSERT_MAILTO: processed ' + CAST(@RowCount AS VARCHAR(10)) + ' row(s).'
END
