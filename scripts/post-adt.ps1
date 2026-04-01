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

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable

    $conn.Open()
    $adapter.Fill($dt) | Out-Null
    $conn.Close()

    return $dt
}

# Step 1: Validate attachments loaded and update log.
function Update-ATDValidation-Post {
    $sqlCommand = @"
UPDATE BLOG
SET
    StatusMessage = CASE
        WHEN ATDT.ATDT_DATA IS NULL THEN 'Stage Error'
        ELSE 'Staged'
    END,
    ErrorMessage = CASE
        WHEN ATDT.ATDT_DATA IS NULL THEN 'ATDT_DATA not found.'
        ELSE NULL
    END,
    AttachmentLoaded = CASE
        WHEN ATDT.ATDT_DATA IS NULL THEN 0
        ELSE 1
    END,
    LoadDate = CASE
        WHEN ATDT.ATDT_DATA IS NOT NULL THEN ATDT.ATXR_CREATE_DT
        ELSE NULL
    END,
    ATXR_DEST_ID = CASE
        WHEN ATDT.ATXR_DEST_ID IS NOT NULL THEN ATDT.ATXR_DEST_ID
        ELSE NULL
    END,
    ATXR_SOURCE_ID = CASE
        WHEN ATDT.ATXR_SOURCE_ID IS NOT NULL THEN ATDT.ATXR_SOURCE_ID
        ELSE NULL
    END,
    MailToDateLoaded = CASE
        WHEN ATNT.ATXR_DEST_ID IS NOT NULL THEN 1
        ELSE 0
    END,
    DestinationDirectoryPath = CASE
        WHEN ATDT.ATDT_DATA IS NOT NULL THEN CONCAT('$($RootDirectoryPath)', '\', BLOG.ATLD_ID)
        ELSE CONCAT(BLOG.SourceDirectoryPath, '\Error')
    END
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
LEFT JOIN (
    SELECT DISTINCT
          CCL.CLCL_ID
        , ATDT.ATDT_DEST_ID
        , ATDT.ATDT_DATA
        , ATDT.ATSY_ID
        , ATDT.ATLD_ID
        , ATXR.ATXR_CREATE_DT
        , ATXR.ATXR_DEST_ID
        , ATXR.ATXR_SOURCE_ID
    FROM Facets..CMC_CLCL_CLAIM CLCL
    JOIN Facets..CER_ATXR_ATTACHLU ATXR
        ON (ATXR.ATXR_SOURCE_ID = CLCL.ATXR_SOURCE_ID)
    JOIN Facets..CER_ATDT_DATA_D ATDT
        ON (ATDT.ATXR_DEST_ID = ATXR.ATXR_DEST_ID)
) AS ATDT
    ON (ATDT.CLCL_ID   = BLOG.CLCL_ID
    AND ATDT.ATDT_DATA = BLOG.ATDT_DATA
    AND ATDT.ATLD_ID   = BLOG.ATLD_ID
    AND ATDT.ATSY_ID   = BLOG.ATSY_ID)
LEFT JOIN Facets..CER_ATNT_DATA_D ATNT
    ON (ATNT.ATXR_DEST_ID = ATDT.ATXR_DEST_ID
    AND ATNT.ATNT_TYPE    = 'ATMD')
WHERE StatusMessage = 'Validated'
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
    StatusMessage IN ('Loaded', 'Stage Error')
"@

    $files = @(Invoke-SQL -DataSource $Datasource -Database "FacetsEXT" -SqlCommand $sqlCommand)

    if ($files.Count -eq 0) {
        Write-Host "Moved 0 files."
        return
    }

    $moved = 0

    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f["SRC"]) {
            Move-Item -LiteralPath $f["SRC"] -Destination $f["DEST"]
            $moved += 1
        }
    }

    Write-Host "Moved $moved files out of $($files.Count) total."
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
        WHEN StatusMessage = 'Staged' AND (MailToDate IS NULL OR MailToDateLoaded = 1) THEN 'Loaded'
        WHEN StatusMessage = 'Staged' AND MailToDate IS NOT NULL AND MailToDateLoaded = 0 THEN 'Stage Error'
        ELSE 'Stage Error'
    END,
    ErrorMessage = CASE
        WHEN StatusMessage = 'Staged' AND MailToDate IS NOT NULL AND MailToDateLoaded = 0 THEN 'MailToDate note not inserted'
        ELSE ErrorMessage
    END
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
WHERE StatusMessage IN ('Staged', 'Stage Error')
"@

    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand $sqlCommand
}

# ----------------------------
# Main
# ----------------------------

try {
    if (-not (Test-Path -LiteralPath $RootDirectoryPath -PathType Container)) {
        throw "Directory not found: $RootDirectoryPath"
    }

    if (-not (Test-Path -LiteralPath $StageDirectoryPath -PathType Container)) {
        throw "Directory not found: $StageDirectoryPath"
    }

    # Step 1: Validate load.
    Update-ATDValidation-Post

    # Step 2: Insert MailToDate notes.
    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand "EXEC FacetsEXT..ADT_INSERT_MAILTO"

    # Step 3: Update log.
    Update-ATDTEndLog

    # Step 4: Move files.
    Move-Files

    # Step 5: Move keyword file to history.
    Move-KeywordFileToHistory

    # Step 6: Move index files to history.
    Move-IndexFilesToHistory

}
catch {
    throw $_
}
