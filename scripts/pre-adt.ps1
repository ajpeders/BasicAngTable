<#
    Validates claim attachment against Facets, moves files into Archive/Error based on validity,
    and generates ATD keyword file.
#>

param (
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

# Step 1a: (Optional) Unzip batch archives and move zip(s) to archive folder.
# Option A (default): one zip per subdirectory.
# Option B: one zip at the root stage directory.
function Expand-StagedZips {
    param (
        [Parameter(Mandatory)]
        [string] $DirectoryPath
    )

    function Move-ZipToArchive {
        param ([string] $ZipPath, [string] $ArchiveDir)
        if (-not (Test-Path -LiteralPath $ArchiveDir)) {
            New-Item -ItemType Directory -Path $ArchiveDir | Out-Null
        }
        Move-Item -LiteralPath $ZipPath -Destination $ArchiveDir
    }

    # Option A: one zip per subdirectory (most likely)
    $subdirs = Get-ChildItem -LiteralPath $DirectoryPath |
        Where-Object { $_.PSIsContainer -and $_.Name -ne "SFTP" }
    foreach ($dir in $subdirs) {
        foreach ($zip in (Get-ChildItem -LiteralPath $dir.FullName -Filter '*.zip')) {
            Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dir.FullName -Force
            Move-ZipToArchive -ZipPath $zip.FullName -ArchiveDir (Join-Path $dir.FullName 'archive')
        }
    }

    # Option B: one zip at root stage directory
    # foreach ($zip in (Get-ChildItem -LiteralPath $DirectoryPath -Filter '*.zip')) {
    #     Expand-Archive -LiteralPath $zip.FullName -DestinationPath $DirectoryPath -Force
    #     Move-ZipToArchive -ZipPath $zip.FullName -ArchiveDir (Join-Path $DirectoryPath 'archive')
    # }
}

# Step 1b: Scan file share for files. MailToDate defaults to file CreationTime.
function Get-FilesFromDisk {
    param (
        [Parameter(Mandatory)]
        [string] $DirectoryPath
    )

    $subdirs = Get-ChildItem -LiteralPath $DirectoryPath |
        Where-Object { $_.PSIsContainer -and $_.Name -ne "SFTP" }

    $files = foreach ($dir in $subdirs) {
        Get-ChildItem -LiteralPath $dir.FullName |
            Where-Object { -not $_.PSIsContainer -and $_.Name -ne 'mailDate.txt' } |
            ForEach-Object {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                $claimId = if ($baseName.Length -ge 12) { $baseName.Substring(0,12) } else { $null }

                [pscustomobject]@{
                    CLCL_ID             = $claimId
                    BaseFilename        = $baseName
                    ATSY_ID             = $dir.Name
                    ATLD_ID             = $dir.Name
                    Extension           = $_.Extension
                    SourceDirectoryPath = $dir.FullName
                    MailToDate          = $_.CreationTime.Date
                }
            }
    }

    return $files
}

# Step 1c: Reads index file per subdirectory and overrides MailToDate on matching files.
# Files not in index are moved to Error folder and excluded from processing.
# Index entries with no matching file are logged to a file in the Error folder.
# Index format: pipe-delimited, quoted cells, with header row.
# Key columns: ClaimNo, LetterID (filename = {ClaimNo}_{LetterID}), ShipDate.
function Get-MailToDateFromIndex {
    param (
        [Parameter(Mandatory)]
        [object[]] $Files
    )

    $matched = [System.Collections.Generic.List[object]]::new()
    $indexPath = Join-Path $StageDirectoryPath 'mailDate.txt'
    if (-not (Test-Path -LiteralPath $indexPath)) {
        Write-Warning "mailDate.txt not found in $StageDirectoryPath — skipping MailToDate override."
        return $Files
    }

    $index   = Import-Csv -LiteralPath $indexPath -Delimiter '|'
    $dateMap = @{}
    foreach ($row in $index) {
        $key = "$($row.ClaimNo)_$($row.LetterID)"
        if ($row.ShipDate) { $dateMap[$key] = [datetime]$row.ShipDate }
    }

    $errorDir = Join-Path $StageDirectoryPath 'Error'
    $fileKeys = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($file in $Files) {
        $null = $fileKeys.Add($file.BaseFilename)
        if ($dateMap.ContainsKey($file.BaseFilename)) {
            $file.MailToDate = $dateMap[$file.BaseFilename]
            $matched.Add($file)
        } else {
            Write-Warning "File '$($file.BaseFilename)' not in index — defaulting MailToDate to today."
            $file.MailToDate = (Get-Date).Date
            $matched.Add($file)
        }
    }

    $orphans = @($dateMap.Keys | Where-Object { -not $fileKeys.Contains($_) })
    if ($orphans.Count -gt 0) {
        if (-not (Test-Path -LiteralPath $errorDir)) {
            New-Item -ItemType Directory -Path $errorDir | Out-Null
        }
        $timestamp = (Get-Date).ToString("MMddyyyy_HHmmss")
        $logPath   = Join-Path $errorDir "index_orphans_${timestamp}.log"
        $orphans | ForEach-Object { "Index entry with no file on disk: $_" } |
            Set-Content -LiteralPath $logPath -Encoding UTF8
        Write-Warning "$($orphans.Count) index entries have no matching file — see $logPath"
    }

    return $matched
}

# Step 2: Insert files into staging table
function Add-FilesToStaging {
    param (
        [Parameter(Mandatory)]
        [object[]] $Files,
        [Parameter(Mandatory)]
        [datetime] $InputDate
    )

    if ($Files.Count -eq 0) { return }

    $batchSize = 1000

    for ($i = 0; $i -lt $Files.Count; $i += $batchSize) {
        $batch = $Files[$i..([Math]::Min($i + $batchSize - 1, $Files.Count - 1))]

        $rows = $batch | ForEach-Object {
            $claimId       = if ($_.CLCL_ID) { "'$($_.CLCL_ID.Replace("'","''"))'" } else { 'NULL' }
            $inputDateStr  = $InputDate.ToString("yyyy-MM-dd HH:mm:ss")
            $appendStr     = $InputDate.ToString("MMddyyyy_HHmmss")
            $mailToDateStr = if ($_.MailToDate) { "'" + ([datetime]$_.MailToDate).ToString("yyyy-MM-dd") + "'" } else { 'NULL' }
            $baseFn        = $_.BaseFilename.Replace("'","''")
            $atsyId        = $_.ATSY_ID.Replace("'","''")
            $atldId        = $_.ATLD_ID.Replace("'","''")
            $srcDir        = $_.SourceDirectoryPath.Replace("'","''")
            $ext           = $_.Extension.Replace("'","''")

            "($claimId, '$inputDateStr', '$baseFn', '$atsyId', '$atldId', '$appendStr', '$srcDir', 0, '$ext', 'Pending', $mailToDateStr)"
        }

        $sqlCommand = @"
INSERT INTO FacetsEXT..ATDT_BATCH_LOG (
    CLCL_ID, InputDate, BaseFilename, ATSY_ID, ATLD_ID, FilenameAppend, SourceDirectoryPath, AttachmentLoaded, Extension, StatusMessage, MailToDate
)
VALUES
$($rows -join ",`n")
"@

        Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand $sqlCommand
    }
}

# Step 3: Validate claims and update log table.
function Update-ATDValidation-Pre {
    $sqlCommand = @"
UPDATE BLOG
SET
    StatusMessage = CASE
        WHEN CCL.CLCL_ID IS NULL THEN 'Stage Error'
        ELSE 'Validated'
    END,
    ErrorMessage = CASE
        WHEN CCL.CLCL_ID IS NULL THEN 'CLCL_ID not found'
        ELSE NULL
    END,
    ATDT_DATA = CONCAT(BLOG.BaseFilename, '_', BLOG.FilenameAppend, BLOG.Extension),
    DestinationDirectoryPath = CASE
        WHEN CCL.CLCL_ID IS NULL THEN CONCAT(BLOG.SourceDirectoryPath, '\Error')
        ELSE NULL
    END
FROM FacetsEXT..ATDT_BATCH_LOG BLOG
LEFT JOIN Facets..CMC_CLCL_CLAIM CCL
    ON CCL.CLCL_ID = BLOG.CLCL_ID
WHERE StatusMessage = 'Pending'
"@

    Invoke-SQL -DataSource $Datasource -Database $Database -SqlCommand $sqlCommand
}

# Step 4: Generate keyword file
function Generate-KeywordFile {
    $sqlCommand = @"
SELECT
    CLCL_ID
  , ATLD_ID
  , ATDT_DATA
FROM
    FacetsEXT..ATDT_BATCH_LOG BLOG
WHERE
    StatusMessage = 'Validated'
"@

    $files = Invoke-SQL -DataSource $Datasource -Database "FacetsEXT" -SqlCommand $sqlCommand

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append("<tagRoot>`n")

    $recId = 0
    foreach ($r in $files) {
        $recId++
        $null = $sb.Append(@"
<INPUT_RECORD>
    <RECORD_ID>$recId</RECORD_ID>
    <ATLD_ID>$($r["ATLD_ID"])</ATLD_ID>
    <FA_RECORD_TYPE> </FA_RECORD_TYPE>
    <KEY_DATA_CLCL_ID>$($r["CLCL_ID"])</KEY_DATA_CLCL_ID>
    <ATDT_DATA>$($r["ATDT_DATA"])</ATDT_DATA>
    <ATTX_DESC>Claim Attachment - Batch</ATTX_DESC>
</INPUT_RECORD>
"@)
    }

    $null = $sb.Append("</tagRoot>")

    $sb.ToString() | Set-Content -LiteralPath (Join-Path $KeywordDirectoryPath $KeywordFilename) -Encoding UTF8

    return $recId
}

# ----------------------------
# Main
# ----------------------------

try {
    if (-not (Test-Path -LiteralPath $StageDirectoryPath -PathType Container)) {
        throw "Directory not found: $StageDirectoryPath"
    }

    if (-not (Test-Path -LiteralPath $KeywordDirectoryPath -PathType Container)) {
        throw "Directory not found: $KeywordDirectoryPath"
    }

    $inputDate = Get-Date

    # Step 1a: (Optional) Unzip batch archives.
    # Expand-StagedZips -DirectoryPath $StageDirectoryPath

    # Step 1b: Scan file share
    $files = @(Get-FilesFromDisk -DirectoryPath $StageDirectoryPath)

    # Step 1c: (Optional) Populate MailToDate from index file.
    # $files = @(Get-MailToDateFromIndex -Files $files)

    Write-Host "Found $($files.Count) files."

    # If no files found, create empty keyword file and exit to avoid downstream errors.
    if ($files.Count -eq 0) {
        '<tagRoot></tagRoot>' | Set-Content -LiteralPath (Join-Path $KeywordDirectoryPath $KeywordFilename) -Encoding UTF8
        Write-Host "No files to process."
        return
    }

    # Step 2: Insert into staging table.
    Add-FilesToStaging -Files $files -InputDate $inputDate
    Write-Host "Inserted $($files.Count) records into staging table."

    # Step 3: Validate and update staging table.
    Update-ATDValidation-Pre

    # Step 4: Generate keyword file.
    $recordCount = Generate-KeywordFile
    Write-Host "Generated keyword file for $($recordCount) attachments."
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    '<tagRoot></tagRoot>' | Set-Content -LiteralPath (Join-Path $KeywordDirectoryPath $KeywordFilename) -Encoding UTF8
    throw $_
}
