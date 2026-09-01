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

request_status() {
    curl -sS \
        -o /tmp/security_body \
        -w "%{http_code}" \
        "$@"
}

echo
echo "============================================================"
echo "API SECURITY / VALIDATION BASELINE"
echo "============================================================"

# ------------------------------------------------------------
# 1. Missing API key
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "1. MISSING API KEY"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "stream": false,
        "max_tokens": 1
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "401" ]; then
    pass "Missing API key -> 401"
else
    fail "Missing API key -> expected 401, got $status"
fi

# ------------------------------------------------------------
# 2. Invalid API key
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "2. INVALID API KEY"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: invalid-key-123" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "stream": false,
        "max_tokens": 1
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "401" ]; then
    pass "Invalid API key -> 401"
else
    fail "Invalid API key -> expected 401, got $status"
fi

# ------------------------------------------------------------
# 3. Empty API key
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "3. EMPTY API KEY"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key:" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "stream": false,
        "max_tokens": 1
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "401" ]; then
    pass "Empty API key -> 401"
else
    fail "Empty API key -> expected 401, got $status"
fi

# ------------------------------------------------------------
# 4. Wrong model
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "4. UNKNOWN MODEL"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "does-not-exist",
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "stream": false,
        "max_tokens": 1
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "404" ]; then
    pass "Unknown model -> 404"
else
    fail "Unknown model -> expected 404, got $status"
fi

# ------------------------------------------------------------
# 5. Malformed JSON
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "5. MALFORMED JSON"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{"model":"qwen-local","messages":[')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "422" ]; then
    pass "Malformed JSON -> 422"
else
    fail "Malformed JSON -> expected 422, got $status"
fi

# ------------------------------------------------------------
# 6. Missing model
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "6. MISSING MODEL"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ]
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "422" ]; then
    pass "Missing model -> 422"
else
    fail "Missing model -> expected 422, got $status"
fi

# ------------------------------------------------------------
# 7. Missing messages
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "7. MISSING MESSAGES"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local"
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "422" ]; then
    pass "Missing messages -> 422"
else
    fail "Missing messages -> expected 422, got $status"
fi

# ------------------------------------------------------------
# 8. Empty messages
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "8. EMPTY MESSAGES"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": []
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "422" ]; then
    pass "Empty messages rejected -> 422"
else
    fail "Empty messages should be rejected -> HTTP $status"
fi

# ------------------------------------------------------------
# 9. Invalid max_tokens type
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "9. INVALID MAX_TOKENS TYPE"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "max_tokens": "invalid"
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "422" ]; then
    pass "Invalid max_tokens type -> 422"
else
    fail "Invalid max_tokens type -> expected 422, got $status"
fi

# ------------------------------------------------------------
# 10. Invalid temperature type
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "10. INVALID TEMPERATURE TYPE"
echo "------------------------------------------------------------"

status=$(request_status \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "temperature": "invalid"
    }')

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "422" ]; then
    pass "Invalid temperature type -> 422"
else
    fail "Invalid temperature type -> expected 422, got $status"
fi

# ------------------------------------------------------------
# 11. GET instead of POST
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "11. WRONG HTTP METHOD"
echo "------------------------------------------------------------"

status=$(request_status \
    -X GET \
    "$BASE_URL/v1/chat/completions" \
    -H "X-API-Key: $VALID_KEY")

echo "HTTP $status"
cat /tmp/security_body
echo

if [ "$status" = "405" ]; then
    pass "GET /v1/chat/completions -> 405"
else
    fail "GET /v1/chat/completions -> expected 405, got $status"
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "============================================================"
echo "SECURITY BASELINE SUMMARY"
echo "============================================================"

echo "PASS : $PASS"
echo "FAIL : $FAIL"

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "SECURITY BASELINE RESULT: PASS"
else
    echo
    echo "SECURITY BASELINE RESULT: FAIL"
fi

rm -f /tmp/security_body

exit "$FAIL"
