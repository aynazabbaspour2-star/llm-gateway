#!/usr/bin/env bash

set -u

BASE_URL="http://localhost:8000"
VALID_KEY="${API_KEY:?API_KEY environment variable is required}"
RATE_KEY="${RATE_TEST_API_KEY:?RATE_TEST_API_KEY environment variable is required}"

PASS=0
FAIL=0

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

check_error_contract() {
    local name="$1"
    local expected_status="$2"
    shift 2

    local headers_file="/tmp/error_headers"
    local body_file="/tmp/error_body"

    echo
    echo "------------------------------------------------------------"
    echo "$name"
    echo "------------------------------------------------------------"

    local status

    status=$(curl -sS \
        -D "$headers_file" \
        -o "$body_file" \
        -w "%{http_code}" \
        "$@")

    echo "HTTP $status"
    cat "$body_file"
    echo

    local ok=1

    if [ "$status" != "$expected_status" ]; then
        fail "$name -> expected HTTP $expected_status, got $status"
        ok=0
    fi

    if ! grep -q '"error"' "$body_file"; then
        fail "$name -> missing error object"
        ok=0
    fi

    if ! grep -q '"message"' "$body_file"; then
        fail "$name -> missing error.message"
        ok=0
    fi

    if ! grep -q '"type"' "$body_file"; then
        fail "$name -> missing error.type"
        ok=0
    fi

    if ! grep -q '"code"' "$body_file"; then
        fail "$name -> missing error.code"
        ok=0
    fi

    if ! grep -qi '^x-request-id:' "$headers_file"; then
        fail "$name -> missing X-Request-ID header"
        ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        pass "$name"
    fi

    rm -f "$headers_file" "$body_file"
}

echo "============================================================"
echo "ERROR CONTRACT CONSISTENCY TEST"
echo "============================================================"

# ------------------------------------------------------------
# 1. Missing API key
# ------------------------------------------------------------

check_error_contract \
    "1. MISSING API KEY" \
    401 \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model":"qwen-local",
        "messages":[{"role":"user","content":"Hello"}]
    }'

# ------------------------------------------------------------
# 2. Invalid API key
# ------------------------------------------------------------

check_error_contract \
    "2. INVALID API KEY" \
    401 \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: definitely-invalid" \
    -d '{
        "model":"qwen-local",
        "messages":[{"role":"user","content":"Hello"}]
    }'

# ------------------------------------------------------------
# 3. Unknown model
# ------------------------------------------------------------

check_error_contract \
    "3. UNKNOWN MODEL" \
    404 \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model":"does-not-exist",
        "messages":[{"role":"user","content":"Hello"}]
    }'

# ------------------------------------------------------------
# 4. Validation error
# ------------------------------------------------------------

check_error_contract \
    "4. VALIDATION ERROR" \
    422 \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model":"qwen-local",
        "messages":[]
    }'

# ------------------------------------------------------------
# 5. Wrong HTTP method
# ------------------------------------------------------------

check_error_contract \
    "5. WRONG HTTP METHOD" \
    405 \
    -X GET "$BASE_URL/v1/chat/completions"

# ------------------------------------------------------------
# 6. Real rate limit
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "6. REAL RATE LIMIT"
echo "------------------------------------------------------------"

echo
echo "Resetting gateway rate-limit state..."

docker restart llm-gateway >/dev/null

sleep 2

rate_tmp_dir=$(mktemp -d)
rate_ok=1

echo "Sending 21 concurrent requests..."

seq 1 21 | xargs -P 21 -I {} sh -c '
    status=$(curl -sS \
        -o "'"$rate_tmp_dir"'/body_{}" \
        -w "%{http_code}" \
        -X POST "'"$BASE_URL"'/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: '"$RATE_KEY"'" \
        -d '"'"'{
            "model":"qwen-local",
            "messages":[{"role":"user","content":"rate test"}]
        }'"'"')

    echo "$status" > "'"$rate_tmp_dir"'/status_{}"
    echo "Request {} -> HTTP $status"
'

total_200=$(grep -h '^200$' "$rate_tmp_dir"/status_* 2>/dev/null | wc -l)
total_429=$(grep -h '^429$' "$rate_tmp_dir"/status_* 2>/dev/null | wc -l)

echo
echo "Rate limit results:"
echo "HTTP 200: $total_200"
echo "HTTP 429: $total_429"

if [ "$total_429" -lt 1 ]; then
    fail "Rate limit -> expected at least one HTTP 429"
    rate_ok=0
else
    pass "Rate limit triggered with concurrent requests"
fi

if [ "$rate_ok" -eq 1 ]; then
    rate_body=$(find "$rate_tmp_dir" -name 'body_*' -type f -exec grep -l '"code":"rate_limit_exceeded"' {} \; | head -n 1)

    if [ -n "$rate_body" ] &&
       grep -q '"error"' "$rate_body" &&
       grep -q '"message"' "$rate_body" &&
       grep -q '"type"' "$rate_body" &&
       grep -q '"code"' "$rate_body"; then
        pass "Rate limit error contract"
    else
        fail "Rate limit error contract"
    fi
fi

rm -rf "$rate_tmp_dir"

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "============================================================"
echo "ERROR CONTRACT SUMMARY"
echo "============================================================"

echo "PASS : $PASS"
echo "FAIL : $FAIL"

echo

if [ "$FAIL" -eq 0 ]; then
    echo "============================================================"
    echo "ERROR CONTRACT RESULT: PASS"
    echo "============================================================"
else
    echo "============================================================"
    echo "ERROR CONTRACT RESULT: FAIL"
    echo "============================================================"
fi

exit "$FAIL"
