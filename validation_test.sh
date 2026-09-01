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
        -o /tmp/validation_body \
        -w "%{http_code}" \
        "$@"
}

check_422() {
    local name="$1"
    shift

    local status
    status=$(request_status "$@")

    echo "HTTP $status"
    cat /tmp/validation_body
    echo

    if [ "$status" = "422" ]; then
        pass "$name -> 422"
    else
        fail "$name -> expected 422, got $status"
    fi
}

check_200() {
    local name="$1"
    shift

    local status
    status=$(request_status "$@")

    echo "HTTP $status"
    cat /tmp/validation_body
    echo

    if [ "$status" = "200" ]; then
        pass "$name -> 200"
    else
        fail "$name -> expected 200, got $status"
    fi
}

echo "============================================================"
echo "VALIDATION V2 TESTS"
echo "============================================================"

echo
echo "------------------------------------------------------------"
echo "1. INVALID MESSAGE ROLE"
echo "------------------------------------------------------------"

check_422 \
    "Invalid message role" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "developer",
                "content": "Hello"
            }
        ]
    }'

echo
echo "------------------------------------------------------------"
echo "2. EMPTY MESSAGE CONTENT"
echo "------------------------------------------------------------"

check_422 \
    "Empty message content" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": ""
            }
        ]
    }'

echo
echo "------------------------------------------------------------"
echo "3. WHITESPACE MESSAGE CONTENT"
echo "------------------------------------------------------------"

check_422 \
    "Whitespace message content" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "   "
            }
        ]
    }'

echo
echo "------------------------------------------------------------"
echo "4. EMPTY MESSAGES ARRAY"
echo "------------------------------------------------------------"

check_422 \
    "Empty messages array" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": []
    }'

echo
echo "------------------------------------------------------------"
echo "5. NEGATIVE TEMPERATURE"
echo "------------------------------------------------------------"

check_422 \
    "Negative temperature" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ],
        "temperature": -0.1
    }'

echo
echo "------------------------------------------------------------"
echo "6. TEMPERATURE ABOVE MAXIMUM"
echo "------------------------------------------------------------"

check_422 \
    "Temperature above 2" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ],
        "temperature": 2.1
    }'

echo
echo "------------------------------------------------------------"
echo "7. ZERO MAX_TOKENS"
echo "------------------------------------------------------------"

check_422 \
    "Zero max_tokens" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ],
        "max_tokens": 0
    }'

echo
echo "------------------------------------------------------------"
echo "8. MAX_TOKENS ABOVE MAXIMUM"
echo "------------------------------------------------------------"

check_422 \
    "max_tokens above 4096" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ],
        "max_tokens": 4097
    }'

echo
echo "------------------------------------------------------------"
echo "9. EMPTY MODEL"
echo "------------------------------------------------------------"

check_422 \
    "Empty model" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ]
    }'

echo
echo "------------------------------------------------------------"
echo "10. WHITESPACE MODEL"
echo "------------------------------------------------------------"

check_422 \
    "Whitespace model" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "   ",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ]
    }'

echo
echo "------------------------------------------------------------"
echo "11. VALID REQUEST"
echo "------------------------------------------------------------"

check_200 \
    "Valid request" \
    -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $VALID_KEY" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Say hello briefly."
            }
        ],
        "temperature": 0.7,
        "max_tokens": 32,
        "stream": false
    }'

echo
echo "============================================================"
echo "VALIDATION V2 SUMMARY"
echo "============================================================"

echo "PASS : $PASS"
echo "FAIL : $FAIL"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "============================================================"
    echo "VALIDATION V2 RESULT: PASS"
    echo "============================================================"
else
    echo "============================================================"
    echo "VALIDATION V2 RESULT: FAIL"
    echo "============================================================"
fi

rm -f /tmp/validation_body

exit "$FAIL"
