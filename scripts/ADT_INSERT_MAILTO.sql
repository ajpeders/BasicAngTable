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
            @NoteDestId      VARCHAR(50),
            @UsusId          VARCHAR(20) = 'BATCH_SVC',
            @NoteAtsyId      VARCHAR(10) = 'ATMO',
            @DefaultDestId   VARCHAR(50) = '1753-01-01T00:00:00',
            @Timestamp       VARCHAR(30)

    CREATE TABLE #GenResult (COL1 VARCHAR(50), COL2 VARCHAR(50), COL3 VARCHAR(50))

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

        -- Step 1: Generate new ATXR_DEST_ID for the note.
        DELETE FROM #GenResult

        INSERT INTO #GenResult
        EXEC Facets..CERSP_ATT0_SELECT_GEN_IDS
            @ATXR_SOURCE_ID = @ATXR_SOURCE_ID,
            @ATSY_ID        = 'ATDT',
            @ATXR_DEST_ID   = @DefaultDestId

        SELECT TOP 1 @NoteDestId = COL3 FROM #GenResult

        IF @NoteDestId IS NULL
        BEGIN
            FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate
            CONTINUE
        END

        -- Step 2: CERSP_ATNT_APPLY — create the note type record.
        EXEC Facets..CERSP_ATNT_APPLY
            @ATSY_ID        = @NoteAtsyId,
            @ATXR_DEST_ID   = @NoteDestId,
            @ATNT_SEQ_NO    = 0,
            @ATNT_TYPE      = 'ATMD',
            @ATXR_ATTACH_ID = @ATXR_DEST_ID

        -- Step 3: CERSP_ATXR_APPLY — create the cross-reference for the note.
        EXEC Facets..CERSP_ATXR_APPLY
            @ATXR_SOURCE_ID      = @ATXR_SOURCE_ID,
            @ATXR_DEST_ID        = @NoteDestId,
            @ATSY_ID             = @ATSY_ID,
            @ATTB_ID             = 'CLCL',
            @ATTB_TYPE           = 'S',
            @ATXR_DESC           = 'Claim Attachment Note',
            @ATXR_CREATE_DT      = @Timestamp,
            @ATXR_CREATE_USUS    = @UsusId,
            @ATXR_LAST_UPD_DT    = @Timestamp,
            @ATXR_LAST_UPD_USUS  = @UsusId,
            @ATXR_COMPILED_KEY   = ''

        -- Step 4: CERSP_ATND_APPLY — insert the note text.
        EXEC Facets..CERSP_ATND_APPLY
            @ATSY_ID        = @NoteAtsyId,
            @ATXR_DEST_ID   = @NoteDestId,
            @ATNT_SEQ_NO    = 0,
            @ATND_SEQ_NO    = 0,
            @ATND_TEXT      = @NoteText

        -- Mark as loaded.
        UPDATE FacetsEXT..ATDT_BATCH_LOG
        SET MailToDateLoaded = 1
        WHERE ATXR_DEST_ID = @ATXR_DEST_ID
          AND ATDT_DATA    = @ATDT_DATA

        FETCH NEXT FROM cur INTO @ATXR_DEST_ID, @ATXR_SOURCE_ID, @ATSY_ID, @ATDT_DATA, @MailToDate
    END

    CLOSE cur
    DEALLOCATE cur
    DROP TABLE #GenResult
END
