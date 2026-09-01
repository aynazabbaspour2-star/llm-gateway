#!/usr/bin/env bash

set -u

BASE_URL="http://localhost:8000"
VALID_KEY="${API_KEY:?API_KEY environment variable is required}"

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

run_test() {
    local name="$1"
    local expected_status="$2"
    local payload="$3"

    echo
    echo "------------------------------------------------------------"
    echo "$name"
    echo "------------------------------------------------------------"

    local status

    status=$(curl -sS \
        -o /tmp/validation_error_body \
        -w "%{http_code}" \
        -X POST "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $VALID_KEY" \
        -H "X-Request-ID: validation-test-$RANDOM" \
        -d "$payload")

    echo "HTTP $status"
    cat /tmp/validation_error_body
    echo

    if [ "$status" != "$expected_status" ]; then
        fail "$name -> expected HTTP $expected_status, got $status"
        return
    fi

    if ! grep -q '"error"' /tmp/validation_error_body; then
        fail "$name -> missing error object"
        return
    fi

    if ! grep -q '"type":"invalid_request_error"' /tmp/validation_error_body; then
        fail "$name -> invalid error type"
        return
    fi

    if ! grep -q '"code":"validation_error"' /tmp/validation_error_body; then
        fail "$name -> invalid error code"
        return
    fi

    pass "$name"
}

echo "============================================================"
echo "VALIDATION ERROR CONTRACT TEST"
echo "============================================================"

run_test \
    "1. EMPTY MESSAGES" \
    422 \
    '{"model":"qwen-local","messages":[]}'

run_test \
    "2. INVALID ROLE" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"invalid","content":"Hello"}]}'

run_test \
    "3. EMPTY CONTENT" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"user","content":""}]}'

run_test \
    "4. WHITESPACE CONTENT" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"user","content":"   "}]}'

run_test \
    "5. TEMPERATURE BELOW RANGE" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"user","content":"Hello"}],"temperature":-1}'

run_test \
    "6. TEMPERATURE ABOVE RANGE" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"user","content":"Hello"}],"temperature":3}'

run_test \
    "7. MAX TOKENS ZERO" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"user","content":"Hello"}],"max_tokens":0}'

run_test \
    "8. MAX TOKENS ABOVE RANGE" \
    422 \
    '{"model":"qwen-local","messages":[{"role":"user","content":"Hello"}],"max_tokens":5000}'

run_test \
    "9. EMPTY MODEL" \
    422 \
    '{"model":"","messages":[{"role":"user","content":"Hello"}]}'

run_test \
    "10. MISSING MODEL" \
    422 \
    '{"messages":[{"role":"user","content":"Hello"}]}'

run_test \
    "11. MISSING MESSAGES" \
    422 \
    '{"model":"qwen-local"}'

echo
echo "============================================================"
echo "VALIDATION ERROR CONTRACT SUMMARY"
echo "============================================================"

echo "PASS : $PASS"
echo "FAIL : $FAIL"

echo

if [ "$FAIL" -eq 0 ]; then
    echo "============================================================"
    echo "VALIDATION ERROR CONTRACT RESULT: PASS"
    echo "============================================================"
else
    echo "============================================================"
    echo "VALIDATION ERROR CONTRACT RESULT: FAIL"
    echo "============================================================"
fi

rm -f /tmp/validation_error_body

exit "$FAIL"
