#!/usr/bin/env bash

set -u

BASE_URL="${BASE_URL:-http://localhost:8000}"
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

echo "========================================"
echo "        LLM GATEWAY FULL TEST"
echo "========================================"
echo

# --------------------------------------------------
# 0. Load API key
# --------------------------------------------------

if [[ ! -f .env ]]; then
    fail ".env file not found"
    exit 1
fi

API_KEYS_LINE=$(grep '^API_KEYS=' .env | cut -d'=' -f2-)

API_KEY=$(printf '%s' "$API_KEYS_LINE" | tr ',' '\n' | awk -F: '$2=="developer" && $4=="true" {print $1; exit}')
RATE_TEST_API_KEY=$(printf '%s' "$API_KEYS_LINE" | tr ',' '\n' | awk -F: '$2=="tester" && $4=="true" {print $1; exit}')
TEST_API_KEY="$API_KEY"

if [[ -n "$API_KEY" ]]; then
    pass "API key loaded"
else
    fail "API key loaded"
    exit 1
fi

if [[ -n "$RATE_TEST_API_KEY" ]]; then
    pass "Rate test API key loaded"
else
    fail "Rate test API key loaded"
    exit 1
fi

if [[ -n "$API_KEY" ]]; then
    pass "API key loaded"
else
    fail "API key loaded"
    exit 1
fi

# --------------------------------------------------
# 1. Health
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_health.json -w "%{http_code}" \
    "$BASE_URL/health")

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '"status":"ok"' /tmp/gw_health.json; then
    pass "Health endpoint"
else
    fail "Health endpoint (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 2. Readiness
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_ready.json -w "%{http_code}" \
    "$BASE_URL/ready")

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '"status":"ready"' /tmp/gw_ready.json; then
    pass "Readiness endpoint"
else
    fail "Readiness endpoint (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 3. Models without authentication
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_noauth_models.json -w "%{http_code}" \
    "$BASE_URL/v1/models")

if [[ "$HTTP_CODE" == "401" ]]; then
    pass "Models reject missing authentication"
else
    fail "Models reject missing authentication (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 4. Models with X-API-Key
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_models.json -w "%{http_code}" \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/models")

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '"id":"qwen-local"' /tmp/gw_models.json; then
    pass "Models with X-API-Key"
else
    fail "Models with X-API-Key (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 5. Models with Bearer
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_bearer.json -w "%{http_code}" \
    -H "Authorization: Bearer $API_KEY" \
    "$BASE_URL/v1/models")

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '"id":"qwen-local"' /tmp/gw_bearer.json; then
    pass "Models with Bearer authentication"
else
    fail "Models with Bearer authentication (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 6. Invalid API key
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_invalid_key.json -w "%{http_code}" \
    -H "X-API-Key: invalid-test-key" \
    "$BASE_URL/v1/models")

if [[ "$HTTP_CODE" == "401" ]]; then
    pass "Invalid API key rejected"
else
    fail "Invalid API key rejected (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 7. Chat completion
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_chat.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Say hello in one short sentence."
            }
        ],
        "stream": false
    }')

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '"choices"' /tmp/gw_chat.json &&
   grep -q '"content"' /tmp/gw_chat.json; then
    pass "Chat completion"
else
    fail "Chat completion (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 8. Chat with Bearer
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_chat_bearer.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Say hello."
            }
        ],
        "stream": false
    }')

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '"choices"' /tmp/gw_chat_bearer.json; then
    pass "Chat completion with Bearer"
else
    fail "Chat completion with Bearer (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 9. Streaming
# --------------------------------------------------

HTTP_CODE=$(curl -N -s -o /tmp/gw_stream.txt -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Say hello in three short words."
            }
        ],
        "stream": true
    }')

if [[ "$HTTP_CODE" == "200" ]] &&
   grep -q '^data:' /tmp/gw_stream.txt &&
   grep -q '^data: \[DONE\]' /tmp/gw_stream.txt; then
    pass "Streaming completion"
else
    fail "Streaming completion (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 10. Invalid model
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_invalid_model.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "model": "does-not-exist",
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ]
    }')

if [[ "$HTTP_CODE" == "400" || "$HTTP_CODE" == "404" ]]; then
    pass "Invalid model rejected"
else
    fail "Invalid model rejected (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 11. Empty messages
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_empty_messages.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "model": "qwen-local",
        "messages": []
    }')

if [[ "$HTTP_CODE" == "400" || "$HTTP_CODE" == "422" ]]; then
    pass "Empty messages rejected"
else
    fail "Empty messages rejected (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 12. Missing model
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_missing_model.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "messages": [
            {
                "role": "user",
                "content": "Hello"
            }
        ]
    }')

if [[ "$HTTP_CODE" == "400" || "$HTTP_CODE" == "422" ]]; then
    pass "Missing model rejected"
else
    fail "Missing model rejected (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 13. Missing messages
# --------------------------------------------------

HTTP_CODE=$(curl -s -o /tmp/gw_missing_messages.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/chat/completions" \
    -d '{
        "model": "qwen-local"
    }')

if [[ "$HTTP_CODE" == "400" || "$HTTP_CODE" == "422" ]]; then
    pass "Missing messages rejected"
else
    fail "Missing messages rejected (HTTP $HTTP_CODE)"
fi

# --------------------------------------------------
# 14. Request ID
# --------------------------------------------------

REQUEST_ID=$(curl -s -D /tmp/gw_headers.txt -o /dev/null \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/models" \
    && grep -i '^x-request-id:' /tmp/gw_headers.txt || true)

if [[ -n "$REQUEST_ID" ]]; then
    pass "Request ID header"
else
    fail "Request ID header"
fi

# --------------------------------------------------
# 15. Rate limit headers
# --------------------------------------------------

curl -s -D /tmp/gw_rate_headers.txt -o /dev/null \
    -H "X-API-Key: $API_KEY" \
    "$BASE_URL/v1/models"

if grep -qi '^x-ratelimit-' /tmp/gw_rate_headers.txt; then
    pass "Rate limit headers"
else
    fail "Rate limit headers"
fi

# --------------------------------------------------
# 16. Existing shell tests
# --------------------------------------------------

TESTS=(
    concurrent_test.sh
    error_contract_test.sh
    regression_test.sh
    security_test.sh
    validation_error_test.sh
    validation_test.sh
)

for test in "${TESTS[@]}"; do
    if [[ -x "$test" ]]; then
        if API_KEY="$API_KEY" RATE_TEST_API_KEY="$RATE_TEST_API_KEY" TEST_API_KEY="$TEST_API_KEY" "./$test" >"/tmp/${test}.log" 2>&1; then
            pass "$test"
        else
            fail "$test"
            cat "/tmp/${test}.log"
        fi
    else
        fail "$test is not executable"
    fi
done

# --------------------------------------------------
# 17. Python syntax
# --------------------------------------------------

if python3 -m py_compile app/main.py fault_proxy.py; then
    pass "Python syntax"
else
    fail "Python syntax"
fi

# --------------------------------------------------
# 18. Shell syntax
# --------------------------------------------------

SHELL_OK=true

for test in "${TESTS[@]}"; do
    if ! bash -n "$test"; then
        SHELL_OK=false
    fi
done

if [[ "$SHELL_OK" == true ]]; then
    pass "Shell syntax"
else
    fail "Shell syntax"
fi

# --------------------------------------------------
# 19. Docker Compose config
# --------------------------------------------------

if docker compose config >/dev/null 2>&1; then
    pass "Docker Compose configuration"
else
    fail "Docker Compose configuration"
fi

# --------------------------------------------------
# 20. Git diff check
# --------------------------------------------------

if git diff --check; then
    pass "Git diff check"
else
    fail "Git diff check"
fi

# --------------------------------------------------
# Summary
# --------------------------------------------------

echo
echo "========================================"
echo "              TEST SUMMARY"
echo "========================================"
echo "PASS : $PASS"
echo "FAIL : $FAIL"
echo "========================================"

if [[ "$FAIL" -eq 0 ]]; then
    echo "RESULT: ALL TESTS PASSED 🔥"
    exit 0
else
    echo "RESULT: TESTS FAILED ❌"
    exit 1
fi
