#!/usr/bin/env bash
# ============================================================
# Claim Attachments — zero-PowerShell E2E test suite
# Requires: bash, curl, jq
#
# Usage:
#   ./test-e2e.sh
#   FUNCTION_BASE_URL=https://apim.example.com/facets ./test-e2e.sh
# ============================================================

set -u

FUNCTION_BASE_URL="${FUNCTION_BASE_URL:-http://localhost:7071/api}"
FUNCTION_CODE="${FUNCTION_CODE:-localkey}"
MOCK_FACETS_BASE_URL="${MOCK_FACETS_BASE_URL:-http://localhost:3001}"
CLAIM_ID="${CLAIM_ID:-TEST-CLAIM-001}"
DIRECTORY="${DIRECTORY:-TESTDIR}"
FILENAME="${FILENAME:-sample_20240115_103000.txt}"
ATXR_SOURCE_ID="${ATXR_SOURCE_ID:-2024-01-15T10:30:00}"
ATXR_DEFAULT_ID="${ATXR_DEFAULT_ID:-1753-01-01T00:00:00}"

# ─── Colours ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;37m'; NC='\033[0m'

PASSED=0; FAILED=0

pass() { echo -e "  [${GREEN}PASS${NC}] $1"; [[ -n "${2:-}" ]] && echo -e "         ${GRAY}$2${NC}"; PASSED=$((PASSED+1)); }
fail() { echo -e "  [${RED}FAIL${NC}] $1"; [[ -n "${2:-}" ]] && echo -e "         ${GRAY}$2${NC}"; FAILED=$((FAILED+1)); }

check() {
    local label="$1" expected="$2" actual="$3" detail="${4:-}"
    if [[ "$actual" == "$expected" ]]; then pass "$label" "$detail"
    else fail "$label" "expected=$expected got=$actual ${detail}"; fi
}

check_contains() {
    local label="$1" needle="$2" haystack="$3" detail="${4:-}"
    if [[ "$haystack" == *"$needle"* ]]; then pass "$label" "$detail"
    else fail "$label" "expected to contain '$needle' — got: $haystack"; fi
}

check_in() {
    local label="$1" actual="$2" detail="${3:-}"
    shift 3
    for v in "$@"; do
        if [[ "$actual" == "$v" ]]; then pass "$label" "$detail"; return; fi
    done
    fail "$label" "got=$actual not in ($(echo "$@" | tr ' ' '|'))"
}

# ─── Fake JWT ────────────────────────────────────────────────
b64url() { printf '%s' "$1" | base64 -w 0 | tr '+' '-' | tr '/' '_' | tr -d '='; }
HEADER=$(b64url '{"alg":"HS256","typ":"JWT"}')
PAYLOAD=$(b64url '{"facets-ususid":"TESTUSER","facets-region":"LOCAL","facets-appid":"test"}')
TOKEN="${HEADER}.${PAYLOAD}.fakesig"

# ─── Helpers ─────────────────────────────────────────────────
download_url() {
    local f="${1}" d="${2}" c="${3}"
    local url="${FUNCTION_BASE_URL}/GetFile?filename=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$f")&dir=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$d")&claimId=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$c")"
    [[ -n "$FUNCTION_CODE" ]] && url="${url}&code=${FUNCTION_CODE}"
    echo "$url"
}

sp_invoke() {
    local proc="$1"
    local params="${2:-}"
    [[ -z "$params" ]] && params="{}"
    curl -s -X POST "${MOCK_FACETS_BASE_URL}/data/procedure/execute" \
        -H "Content-Type: application/json" \
        -d "{\"Procedure\":\"${proc}\",\"Parameters\":${params},\"Analyze\":false,\"Identity\":\"SVCAGENT\"}"
}

# ─── Header ──────────────────────────────────────────────────
echo ""
echo -e "${CYAN}Claim Attachments E2E Tests (bash/curl)${NC}"
echo "  Function : ${FUNCTION_BASE_URL}"
echo "  Facets   : ${MOCK_FACETS_BASE_URL}"
echo "  ClaimId  : ${CLAIM_ID}"
echo ""

# ════════════════════════════════════════════════════════════
echo -e "${YELLOW}── 1. GetFile — successful download ──────────────────────${NC}"
url=$(download_url "$FILENAME" "$DIRECTORY" "$CLAIM_ID")
resp=$(curl -s -D /tmp/resp_headers.txt -o /tmp/resp_body.txt -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" "$url")
check "HTTP 200" "200" "$resp"
body_len=$(wc -c < /tmp/resp_body.txt)
[[ "$body_len" -gt 0 ]] && pass "Response body non-empty" "Bytes=${body_len}" || fail "Response body non-empty" "Bytes=0"
cd_header=$(grep -i '^content-disposition:' /tmp/resp_headers.txt | head -1 | tr -d '\r\n')
check_contains "Content-Disposition: inline" "inline" "$cd_header" "$cd_header"
ct_header=$(grep -i '^content-type:' /tmp/resp_headers.txt | head -1 | tr -d '\r\n')
check_contains "Content-Type: text/plain" "text/plain" "$ct_header" "$ct_header"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 2. GetFile — missing bearer token → 401 ───────────────${NC}"
code=$(curl -s -o /dev/null -w "%{http_code}" "$(download_url "$FILENAME" "$DIRECTORY" "$CLAIM_ID")")
check "HTTP 401" "401" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 3. GetFile — bad claimId → 403 ─────────────────────────${NC}"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    "$(download_url "$FILENAME" "$DIRECTORY" "BADCLAIM-999")")
check "HTTP 403" "403" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 4. GetFile — missing filename → 400 ────────────────────${NC}"
url="${FUNCTION_BASE_URL}/GetFile?dir=${DIRECTORY}&claimId=${CLAIM_ID}"
[[ -n "$FUNCTION_CODE" ]] && url="${url}&code=${FUNCTION_CODE}"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${TOKEN}" "$url")
check "HTTP 400 (missing filename)" "400" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 5. GetFile — missing dir → 400 ─────────────────────────${NC}"
url="${FUNCTION_BASE_URL}/GetFile?filename=${FILENAME}&claimId=${CLAIM_ID}"
[[ -n "$FUNCTION_CODE" ]] && url="${url}&code=${FUNCTION_CODE}"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${TOKEN}" "$url")
check "HTTP 400 (missing dir)" "400" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 6. GetFile — missing claimId → 400 ─────────────────────${NC}"
url="${FUNCTION_BASE_URL}/GetFile?filename=${FILENAME}&dir=${DIRECTORY}"
[[ -n "$FUNCTION_CODE" ]] && url="${url}&code=${FUNCTION_CODE}"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${TOKEN}" "$url")
check "HTTP 400 (missing claimId)" "400" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 7. GetFile — file not found → 404 ──────────────────────${NC}"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    "$(download_url "doesnotexist_99999999.txt" "$DIRECTORY" "$CLAIM_ID")")
check "HTTP 404 (file not found)" "404" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 8. GetFile — path traversal is sanitized ───────────────${NC}"
traversal_enc=$(python3 -c "import urllib.parse;print(urllib.parse.quote('../../../etc/passwd'))")
url="${FUNCTION_BASE_URL}/GetFile?filename=${traversal_enc}&dir=${DIRECTORY}&claimId=${CLAIM_ID}"
[[ -n "$FUNCTION_CODE" ]] && url="${url}&code=${FUNCTION_CODE}"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${TOKEN}" "$url")
check_in "Traversal → 400 or 404 (never 200/500)" "$code" "Got HTTP ${code}" "400" "404"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 9. Upload — successful upload ──────────────────────────${NC}"
UPLOADED_FILENAME=""
tmpfile=$(mktemp /tmp/e2e-upload-XXXXXX.txt)
echo -e "E2E test attachment content\nCreated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmpfile"
upload_url="${FUNCTION_BASE_URL}/upload"
[[ -n "$FUNCTION_CODE" ]] && upload_url="${upload_url}?code=${FUNCTION_CODE}"
upload_resp=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@${tmpfile};type=text/plain" \
    -F "dir=${DIRECTORY}" \
    -F "claimId=${CLAIM_ID}" \
    "$upload_url")
upload_code=$(echo "$upload_resp" | tail -1)
upload_body=$(echo "$upload_resp" | head -n -1)
rm -f "$tmpfile"
check "HTTP 200" "200" "$upload_code"
upload_success=$(echo "$upload_body" | jq -r '.success // false')
check "success=true" "true" "$upload_success"
UPLOADED_FILENAME=$(echo "$upload_body" | jq -r '.filename // ""')
[[ -n "$UPLOADED_FILENAME" ]] && pass "Response includes timestamped filename" "filename=${UPLOADED_FILENAME}" \
                               || fail "Response includes timestamped filename" "filename was empty"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 10. Upload — non-viewable type served as attachment ─────${NC}"
docx_file=$(ls "$(dirname "$0")/mock-server/filestore/testshare/${DIRECTORY}/test_"*.docx 2>/dev/null | tail -1)
if [[ -n "$docx_file" ]]; then
    docx_name=$(basename "$docx_file")
    curl -s -D /tmp/docx_headers.txt -o /dev/null \
        -H "Authorization: Bearer ${TOKEN}" \
        "$(download_url "$docx_name" "$DIRECTORY" "$CLAIM_ID")"
    docx_cd=$(grep -i '^content-disposition:' /tmp/docx_headers.txt | head -1 | tr -d '\r\n')
    check_contains "Content-Disposition: attachment" "attachment" "$docx_cd" "$docx_cd"
else
    echo -e "  ${GRAY}[SKIP] No .docx in filestore — run test 9 (upload) first${NC}"
fi

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 11. Upload — missing bearer token → 401 ────────────────${NC}"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    -F "dir=${DIRECTORY}" -F "claimId=${CLAIM_ID}" \
    "$upload_url")
check "HTTP 401 (no token)" "401" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 12. Upload — bad claimId → 403 ─────────────────────────${NC}"
bad_tmp=$(mktemp /tmp/e2e-bad-XXXXXX.txt)
echo "bad claim test" > "$bad_tmp"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@${bad_tmp};type=text/plain" \
    -F "dir=${DIRECTORY}" \
    -F "claimId=BADCLAIM-999" \
    "$upload_url")
rm -f "$bad_tmp"
check "HTTP 403 (bad claimId)" "403" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 13. Upload — missing dir → 400 ─────────────────────────${NC}"
miss_dir_tmp=$(mktemp /tmp/e2e-missdir-XXXXXX.txt)
echo "missing dir test" > "$miss_dir_tmp"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@${miss_dir_tmp};type=text/plain" \
    -F "claimId=${CLAIM_ID}" \
    "$upload_url")
rm -f "$miss_dir_tmp"
check "HTTP 400 (missing dir)" "400" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 14. Upload — missing file → 400 ────────────────────────${NC}"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "dir=${DIRECTORY}" \
    -F "claimId=${CLAIM_ID}" \
    "$upload_url")
check "HTTP 400 (missing file)" "400" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 15. Upload — verify uploaded file is downloadable ───────${NC}"
if [[ -n "$UPLOADED_FILENAME" ]]; then
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${TOKEN}" \
        "$(download_url "$UPLOADED_FILENAME" "$DIRECTORY" "$CLAIM_ID")")
    check "HTTP 200 (get uploaded file)" "200" "$code"
else
    echo -e "  ${GRAY}[SKIP] Upload failed, skipping download verification${NC}"
fi

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 16. Facets REST — config/browser/:region ────────────────${NC}"
resp=$(curl -s "${MOCK_FACETS_BASE_URL}/RestServices/facets/api/v1/config/browser/LOCAL")
data=$(echo "$resp" | jq -r '.Data // empty')
[[ -n "$data" ]] && pass "200 with Data field" "Data=${data}" || fail "200 with Data field" "resp=${resp}"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 17. Facets REST — claims/:claimId (granted) ─────────────${NC}"
resp=$(curl -s "${MOCK_FACETS_BASE_URL}/RestServices/facets/api/v1/claims/${CLAIM_ID}")
access=$(echo "$resp" | jq -r '.Data.Access // empty')
check "Access=Granted" "Granted" "$access"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 18. Facets REST — claims/:claimId (denied → 403) ────────${NC}"
code=$(curl -s -o /dev/null -w "%{http_code}" \
    "${MOCK_FACETS_BASE_URL}/RestServices/facets/api/v1/claims/BADCLAIM-999")
check "HTTP 403 (unknown claim)" "403" "$code"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 19. Facets REST — attachments/entities/CLCL ────────────${NC}"
atxr_enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$ATXR_SOURCE_ID")
resp=$(curl -s "${MOCK_FACETS_BASE_URL}/RestServices/facets/api/v1/attachments/entities/CLCL?ATXR_SOURCE_ID=${atxr_enc}")
row_count=$(echo "$resp" | jq '.Data.Attachments.ATDT_COLL | length')
[[ "$row_count" -gt 0 ]] && pass "Returns at least one attachment row" "Rows=${row_count}" \
                          || fail "Returns at least one attachment row" "Rows=0"
atdt_data=$(echo "$resp" | jq -r '.Data.Attachments.ATDT_COLL[0].ATDT_DATA // ""')
check_contains "ATDT_DATA is a .txt filename" ".txt" "$atdt_data" "ATDT_DATA=${atdt_data}"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 20. SP invoke — CERSP_ATSY_SEARCH_ATTB_ID (dir dropdown) ${NC}"
resp=$(sp_invoke "CERSP_ATSY_SEARCH_ATTB_ID" "{}")
dir_count=$(echo "$resp" | jq '.Data.ResultSets[0].Rows | length')
[[ "$dir_count" -ge 1 ]] && pass "Returns directory rows" "Count=${dir_count}" \
                          || fail "Returns directory rows" "Count=0"
atsy_id=$(echo "$resp" | jq -r '.Data.ResultSets[0].Rows[0].ATSY_ID // ""')
atsy_desc=$(echo "$resp" | jq -r '.Data.ResultSets[0].Rows[0].ATSY_DESC // ""')
[[ -n "$atsy_id" && -n "$atsy_desc" ]] && pass "First row has ATSY_ID + ATSY_DESC" "ATSY_ID=${atsy_id} ATSY_DESC=${atsy_desc}" \
                                        || fail "First row has ATSY_ID + ATSY_DESC" "ATSY_ID=${atsy_id} ATSY_DESC=${atsy_desc}"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 21. SP chain — note submission (submitNoteForm) ─────────${NC}"
resp=$(sp_invoke "CERSP_ATTO_SELECT_GEN_IDS" \
    "{\"ATXR_SOURCE_ID\":\"${ATXR_SOURCE_ID}\",\"ATSY_ID\":\"ATDT\",\"ATXR_DEST_ID\":\"${ATXR_DEFAULT_ID}\"}")
NOTE_ATXR_DEST=$(echo "$resp" | jq -r '.Data.ResultSets[0].Rows[0].COL3 // ""')
[[ -n "$NOTE_ATXR_DEST" ]] && pass "CERSP_ATTO_SELECT_GEN_IDS — got COL3" "ATXR_DEST_ID=${NOTE_ATXR_DEST}" \
                            || fail "CERSP_ATTO_SELECT_GEN_IDS — got COL3" "COL3 was empty"
DEST="${NOTE_ATXR_DEST:-gen-dest-001}"

for proc in CERSP_ATNT_APPLY CERSP_ATXR_APPLY CERSP_ATND_APPLY; do
    r=$(sp_invoke "$proc" "{\"ATXR_DEST_ID\":\"${DEST}\"}")
    has_rs=$(echo "$r" | jq 'if .Data.ResultSets != null then "yes" else "no" end' -r)
    check "$proc returns ResultSets" "yes" "$has_rs"
done

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 22. SP chain — long note chunking (250 chars → 3 chunks) ${NC}"
long_note=$(python3 -c "print('A'*250)")
chunk_pass=0
for i in 0 1 2; do
    start=$((i * 100))
    chunk=$(echo "$long_note" | cut -c$((start+1))-$((start+100)))
    chunk_len=${#chunk}
    params="{\"ATSY_ID\":\"ATDT\",\"ATXR_DEST_ID\":\"${DEST}\",\"ATNT_SEQ_NO\":0,\"ATND_SEQ_NO\":${i},\"ATND_TEXT\":\"${chunk}\"}"
    r=$(sp_invoke "CERSP_ATND_APPLY" "$params")
    has_rs=$(echo "$r" | jq 'if .Data.ResultSets != null then "yes" else "no" end' -r)
    if [[ "$has_rs" == "yes" ]]; then
        pass "  CERSP_ATND_APPLY chunk ${i} (len=${chunk_len})"
        chunk_pass=$((chunk_pass+1))
    else
        fail "  CERSP_ATND_APPLY chunk ${i} (len=${chunk_len})"
    fi
done
[[ "$chunk_pass" -eq 3 ]] && pass "All 3 chunks sent successfully" "3/3 passed" \
                           || fail "All 3 chunks sent successfully" "${chunk_pass}/3 passed"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 23. SP chain — new-claim path (CMCSP_CLCL_APPLY) ───────${NC}"
resp=$(sp_invoke "CERSP_ATTO_SELECT_GEN_IDS" \
    "{\"ATXR_SOURCE_ID\":\"${ATXR_DEFAULT_ID}\",\"ATSY_ID\":\"ATDT\",\"ATXR_DEST_ID\":\"${ATXR_DEFAULT_ID}\"}")
NEW_SRC=$(echo "$resp" | jq -r '.Data.ResultSets[0].Rows[0].COL1 // ""')
[[ -n "$NEW_SRC" ]] && pass "CERSP_ATTO_SELECT_GEN_IDS — got COL1" "COL1=${NEW_SRC}" \
                    || fail "CERSP_ATTO_SELECT_GEN_IDS — got COL1" "COL1 was empty"
SRC="${NEW_SRC:-gen-src-001}"

r=$(sp_invoke "CMCSP_CLCL_APPLY" \
    "{\"CLCL_ID\":\"${CLAIM_ID}\",\"ATXR_SOURCE_ID\":\"${SRC}\",\"CLCL_STATUS\":\"O\"}")
has_rs=$(echo "$r" | jq 'if .Data.ResultSets != null then "yes" else "no" end' -r)
check "CMCSP_CLCL_APPLY returns ResultSets" "yes" "$has_rs" "ATXR_SOURCE_ID used=${SRC}"

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}── 24. SP chain — full upload registration ─────────────────${NC}"
resp=$(sp_invoke "CERSP_ATTO_SELECT_GEN_IDS" \
    "{\"ATXR_SOURCE_ID\":\"${ATXR_SOURCE_ID}\",\"ATSY_ID\":\"ATDT\",\"ATXR_DEST_ID\":\"${ATXR_DEFAULT_ID}\"}")
UP_DEST=$(echo "$resp" | jq -r '.Data.ResultSets[0].Rows[0].COL3 // ""')
[[ -n "$UP_DEST" ]] && pass "CERSP_ATTO_SELECT_GEN_IDS (upload reg) — got ATXR_DEST_ID" "ATXR_DEST_ID=${UP_DEST}" \
                    || fail "CERSP_ATTO_SELECT_GEN_IDS (upload reg)" "COL3 was empty"
UP_DEST="${UP_DEST:-gen-dest-001}"

for proc in CERSP_ATDT_APPLY CERSP_ATXR_APPLY CERSP_ATNT_APPLY CERSP_ATND_APPLY; do
    r=$(sp_invoke "$proc" "{}")
    has_rs=$(echo "$r" | jq 'if .Data.ResultSets != null then "yes" else "no" end' -r)
    check "$proc" "yes" "$has_rs"
done

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo -e "${GRAY}─────────────────────────────────────${NC}"
TOTAL=$((PASSED+FAILED))
if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${GREEN}Results: ${PASSED}/${TOTAL} passed${NC}"
else
    echo -e "${YELLOW}Results: ${PASSED}/${TOTAL} passed  (${RED}${FAILED} failed${NC}${YELLOW})${NC}"
    exit 1
fi
