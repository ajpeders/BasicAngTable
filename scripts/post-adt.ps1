param (
    [Parameter(Mandatory)][string] $RootDirectoryPath,
    [Parameter(Mandatory)][string] $StageDirectoryPath,
    [Parameter(Mandatory)][string] $KeywordDirectoryPath,
    [Parameter(Mandatory)][string] $KeywordFilename,
    [Parameter(Mandatory)][string] $Datasource,
    [string] $Database = 'Facets'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------
# Functions
# ----------------------------

# Execute sql query.
function Invoke-SQL {
    param (
        [Parameter(Mandatory)]
        [string] $DataSource,
        [Parameter(Mandatory)]
        [string] $Database,
        [Parameter(Mandatory)]
        [string] $SqlCommand
    )

    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Data Source=$DataSource; Integrated Security=SSPI; Initial Catalog=$Database"

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $SqlCommand
    $conn.Open()

    $isSelect = $SqlCommand.TrimStart() -match '^SELECT'
    if ($isSelect) {
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $dt = New-Object System.Data.DataTable
        $null = $adapter.Fill($dt)
        $conn.Close()
        Write-Host "  SQL: $($dt.Rows.Count) row(s) returned."
        return $dt
    } else {
        $rowsAffected = $cmd.ExecuteNonQuery()
        $conn.Close()
        Write-Host "  SQL: $rowsAffected row(s) affected."
    }
}

# Step 1: Validate attachments loaded and update log.
function Update-ATDValidation-Post {
    $sqlCommand = @"
UPDATE BLOG
SET
    StatusMessage = CASE
        WHEN FA.ATDT_DATA IS NULL THEN 'Stage Error'
        ELSE 'Staged'
    END,
    ErrorMessage = CASE
        WHEN FA.ATDT_DATA IS NULL THEN 'ATDT_DATA not found.'
        ELSE NULL
    END,
    AttachmentLoaded = CASE
        WHEN FA.ATDT_DATA IS NULL THEN 0
        ELSE 1
    END,
    LoadDate = CASE
        WHEN FA.ATDT_DATA IS NOT NULL THEN FA.ATXR_CREATE_DT
        ELSE NULL
    END,
    ATXR_DEST_ID = FA.ATXR_DEST_ID,
    ATXR_SOURCE_ID = FA.ATXR_SOURCE_ID,
    MailToDateLoaded = 0,
    DestinationDirectoryPath = CASE
        WHEN FA.ATDT_DATA IS NOT NULL THEN CONCAT('$($RootDirectoryPath.Replace("'","''"))', '\', BLOG.ATLD_ID)
        ELSE CONCAT(BLOG.SourceDirectoryPath, '\Error')
    END
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
LEFT JOIN (
    SELECT DISTINCT
          CLCL.CLCL_ID
        , ATDT.ATDT_DATA
        , ATDT.ATSY_ID
        , ATDT.ATLD_ID
        , ATXR.ATXR_CREATE_DT
        , ATXR.ATXR_DEST_ID
        , ATXR.ATXR_SOURCE_ID
    FROM Facets..CMC_CLCL_CLAIM CLCL
    JOIN Facets..CER_ATXR_ATTACH_U ATXR
        ON (ATXR.ATXR_SOURCE_ID = CLCL.ATXR_SOURCE_ID)
    JOIN Facets..CER_ATDT_DATA_D ATDT
        ON (ATDT.ATXR_DEST_ID = ATXR.ATXR_DEST_ID)
) AS FA
    ON (FA.CLCL_ID   = BLOG.CLCL_ID
    AND FA.ATDT_DATA = BLOG.ATDT_DATA
    AND FA.ATLD_ID   = BLOG.ATLD_ID
    AND FA.ATSY_ID   = BLOG.ATSY_ID)
WHERE BLOG.StatusMessage = 'Validated'
"@

    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand $sqlCommand
}

function Move-Files {
    $sqlCommand = @"
SELECT
      SRC  = CONCAT(SourceDirectoryPath, '\', BaseFilename, Extension)
    , DEST = CONCAT(DestinationDirectoryPath, '\', ATDT_DATA)
FROM
    FacetsEXT..ATDT_BATCH_LOG
WHERE
    StatusMessage = 'Loaded'
"@

    $files = @(Invoke-SQL -DataSource $Datasource -Database "FacetsEXT" -SqlCommand $sqlCommand)

    if ($files.Count -eq 0) {
        Write-Host "Moved 0 files."
        return
    }

    $moved = 0

    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f["SRC"]) {
            $destDir = [System.IO.Path]::GetDirectoryName($f["DEST"])
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Move-Item -LiteralPath $f["SRC"] -Destination $f["DEST"] -Force
            $moved += 1
        }
    }

    Write-Host "Moved $moved files out of $($files.Count) total."
}

function Update-StatusComplete {
    $sqlCommand = @"
UPDATE FacetsEXT..ATDT_BATCH_LOG
SET StatusMessage = 'Complete'
WHERE StatusMessage = 'Loaded'
"@

    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand $sqlCommand
}

function Move-KeywordFileToHistory {
    $historyPath = Join-Path $KeywordDirectoryPath 'history'

    if (-not (Test-Path -LiteralPath $historyPath)) {
        New-Item -ItemType Directory -Path $historyPath | Out-Null
    }

    $src = Join-Path $KeywordDirectoryPath $KeywordFilename
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "Keyword file not found, skipping history move."
        return
    }

    $timestamp = (Get-Date).ToString("MMddyyyy_HHmmss")
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($KeywordFilename)
    $dest      = Join-Path $historyPath "${baseName}_${timestamp}.kwd"

    Move-Item -LiteralPath $src -Destination $dest
    Write-Host "Keyword file moved to history: $dest"
}

function Move-IndexFilesToHistory {
    $src = Join-Path $StageDirectoryPath 'mailDate.txt'
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "mailDate.txt not found, skipping history move."
        return
    }

    $historyPath = Join-Path $StageDirectoryPath 'history'
    if (-not (Test-Path -LiteralPath $historyPath)) {
        New-Item -ItemType Directory -Path $historyPath | Out-Null
    }

    $timestamp = (Get-Date).ToString("MMddyyyy_HHmmss")
    $dest = Join-Path $historyPath "mailDate_${timestamp}.txt"
    Move-Item -LiteralPath $src -Destination $dest
    Write-Host "Index file moved to history: $dest"
}

function Update-ATDTEndLog {
    $sqlCommand = @"
UPDATE BLOG
SET
    StatusMessage = CASE
        WHEN StatusMessage = 'Staged' THEN 'Loaded'
        ELSE StatusMessage
    END,
    ErrorMessage = CASE
        WHEN StatusMessage = 'Staged' AND MailToDate IS NOT NULL AND MailToDateLoaded = 0 THEN 'MailToDate note pending'
        ELSE ErrorMessage
    END
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
WHERE StatusMessage = 'Staged'
"@

    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand $sqlCommand
}

# ----------------------------
# Main
# ----------------------------

try {
    Write-Host "=== post-adt START ==="

    if (-not (Test-Path -LiteralPath $RootDirectoryPath -PathType Container)) {
        throw "Directory not found: $RootDirectoryPath"
    }

    if (-not (Test-Path -LiteralPath $StageDirectoryPath -PathType Container)) {
        throw "Directory not found: $StageDirectoryPath"
    }

    Write-Host "Directories validated."

    # Diagnostic: show batch log state before processing.
    Write-Host ""
    Write-Host "--- DIAGNOSTICS ---"
    $diag = Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand @"
SELECT
    StatusMessage,
    Cnt = COUNT(*),
    HasATXR = SUM(CASE WHEN ATXR_DEST_ID IS NOT NULL THEN 1 ELSE 0 END),
    HasMailTo = SUM(CASE WHEN MailToDate IS NOT NULL THEN 1 ELSE 0 END)
FROM FacetsEXT..ATDT_BATCH_LOG
GROUP BY StatusMessage
"@
    foreach ($row in $diag) {
        Write-Host "  Status=$($row['StatusMessage'])  Count=$($row['Cnt'])  HasATXR=$($row['HasATXR'])  HasMailTo=$($row['HasMailTo'])"
    }
    Write-Host "-------------------"
    Write-Host ""

    # Step 1: Validate load.
    Write-Host "Step 1: Validating attachment load..."
    Update-ATDValidation-Post
    Write-Host "Step 1: Done."

    # Step 2: Insert MailToDate notes.
    Write-Host "Step 2: Inserting MailToDate notes..."
    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand "EXEC FacetsEXT..ADT_INSERT_MAILTO"
    Write-Host "Step 2: Done."

    # Step 3: Update log.
    Write-Host "Step 3: Updating end log..."
    Update-ATDTEndLog
    Write-Host "Step 3: Done."

    # Step 4: Move files.
    Write-Host "Step 4: Moving files..."
    Move-Files

    # Step 5: Move keyword file to history.
    Write-Host "Step 5: Moving keyword file to history..."
    Move-KeywordFileToHistory

    # Step 6: Move index files to history.
    Write-Host "Step 6: Moving index files to history..."
    Move-IndexFilesToHistory

    # Step 7: Mark all processed rows as Complete.
    Write-Host "Step 7: Marking rows as Complete..."
    Update-StatusComplete
    Write-Host "Step 7: Done."

    Write-Host "=== post-adt COMPLETE ==="
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    throw $_
}
