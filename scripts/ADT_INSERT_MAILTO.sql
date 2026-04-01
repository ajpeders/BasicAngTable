CREATE OR ALTER PROCEDURE FacetsEXT..ADT_INSERT_MAILTO
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ATXR_DEST_ID    VARCHAR(50),
            @ATXR_SOURCE_ID  VARCHAR(50),
            @ATSY_ID         VARCHAR(10),
            @ATDT_DATA       VARCHAR(255),
            @MailToDate      DATE,
            @NoteText        VARCHAR(300),
            @NoteDestId      DATETIME,
            @UsusId          VARCHAR(20) = 'BATCH_SVC',
            @NoteAtsyId      VARCHAR(10) = 'ATMO',
            @Timestamp       VARCHAR(30)

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

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @NoteText  = 'MailToDate for ' + @ATDT_DATA + ': ' + CONVERT(VARCHAR(10), @MailToDate, 101)
        SET @Timestamp = CONVERT(VARCHAR(30), GETDATE(), 126)

        -- Generate new ATXR_DEST_ID from sequence table.
        UPDATE Facets..CER_SEQS_SEQUENCE
        SET SEQS_CURRENT_DTM = SEQS_CURRENT_DTM
        WHERE SEQS_SPID = @@SPID % 2000

        SELECT @NoteDestId = DATEADD(MILLISECOND, 10, SEQS_CURRENT_DTM)
        FROM Facets..CER_SEQS_SEQUENCE
        WHERE SEQS_SPID = @@SPID % 2000

        IF @NoteDestId IS NULL
        BEGIN
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
            ATXR_LAST_UPD_DT, ATXR_LAST_UPD_USUS, ATXR_COMPILED_KEY
        )
        VALUES (
            @ATXR_SOURCE_ID, @NoteDestId, @ATSY_ID, 'CLCL', 'S',
            'Claim Attachment Note', @Timestamp, @UsusId,
            @Timestamp, @UsusId, ''
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

        FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate
    END

    CLOSE cur
    DEALLOCATE cur
END
