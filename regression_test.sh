#!/usr/bin/env bash

set -u

BASE_URL="http://localhost:8000"
API_KEY="${API_KEY:?API_KEY environment variable is required}"
TEST_API_KEY="${TEST_API_KEY:?TEST_API_KEY environment variable is required}"
RATE_TEST_API_KEY="${RATE_TEST_API_KEY:?RATE_TEST_API_KEY environment variable is required}"

PASS=0
FAIL=0
SKIP=0

ORIGINAL_ENV_BACKUP="/tmp/llm-gateway-regression-env-backup"

restore_environment() {
    echo
    echo "============================================================"
    echo "REGRESSION CLEANUP"
    echo "============================================================"

    if [ -f "$ORIGINAL_ENV_BACKUP" ]; then
        cp "$ORIGINAL_ENV_BACKUP" .env
        echo "Restored .env"
    fi

    # Stop fault proxy if it exists.
    if docker ps -q --filter "name=^llm-fault-proxy$" | grep -q .; then
        docker stop llm-fault-proxy >/dev/null 2>&1 || true
        echo "Stopped fault proxy"
    fi

    # Restore real backend configuration.
    docker compose up -d --force-recreate gateway >/dev/null 2>&1 || true

    # Wait for gateway health.
    for _ in $(seq 1 30); do
        if [ "$(docker inspect -f '{{.State.Health.Status}}' llm-gateway 2>/dev/null)" = "healthy" ]; then
            echo "Gateway restored and healthy"
            break
        fi
        sleep 2
    done
}

# Always restore the environment when the script exits.
trap restore_environment EXIT

cp .env "$ORIGINAL_ENV_BACKUP"

print_header() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

skip() {
    echo "SKIP: $1"
    SKIP=$((SKIP + 1))
}

# ------------------------------------------------------------
# Common request
# ------------------------------------------------------------

chat_request() {
    local api_key="$1"
    local request_id="$2"
    local stream="$3"

    curl -sS \
        -X POST \
        "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $api_key" \
        -H "X-Request-ID: $request_id" \
        -d "{
            \"model\": \"qwen-local\",
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": \"Say hello.\"
                }
            ],
            \"stream\": $stream,
            \"max_tokens\": 5
        }"
}

# ============================================================
# 1. GATEWAY HEALTH
# ============================================================

print_header "1. GATEWAY HEALTH"

gateway_status=$(curl -sS -o /dev/null -w "%{http_code}" \
    "$BASE_URL/health")

if [ "$gateway_status" = "200" ]; then
    pass "Gateway health"
else
    fail "Gateway health (HTTP $gateway_status)"
fi

# ============================================================
# 2. BACKEND HEALTH
# ============================================================

print_header "2. BACKEND HEALTH"

backend_status=$(curl -sS -o /dev/null -w "%{http_code}" \
    "http://localhost:8081/health")

if [ "$backend_status" = "200" ]; then
    pass "Backend health"
else
    fail "Backend health (HTTP $backend_status)"
fi

# ============================================================
# 3. NORMAL NON-STREAM
# ============================================================

print_header "3. NORMAL NON-STREAM"

response=$(chat_request "$API_KEY" "regression-nonstream" "false")

if echo "$response" | grep -q '"choices"'; then
    pass "Normal non-stream response"
else
    fail "Normal non-stream response"
    echo "$response"
fi

# ============================================================
# 4. NORMAL STREAMING
# ============================================================

print_header "4. NORMAL STREAMING"

stream_output=$(chat_request "$API_KEY" "regression-stream" "true")

if echo "$stream_output" | grep -q '^data:' &&
   echo "$stream_output" | grep -q 'data: \[DONE\]'; then

    pass "Normal OpenAI-compatible streaming"
else
    fail "Normal OpenAI-compatible streaming"
    echo "$stream_output"
fi

# ============================================================
# 5. REQUEST ID PROPAGATION
# ============================================================

print_header "5. REQUEST ID PROPAGATION"

request_id="regression-request-id"

headers=$(curl -sS -D - -o /dev/null \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -H "X-Request-ID: $request_id" \
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

if echo "$headers" | grep -qi "^x-request-id: $request_id"; then
    pass "X-Request-ID propagation"
else
    fail "X-Request-ID propagation"
    echo "$headers"
fi

# ============================================================
# 6. RATE LIMIT HEADERS
# ============================================================

print_header "6. RATE LIMIT HEADERS"

rate_headers=$(curl -sS -D - -o /dev/null \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $TEST_API_KEY" \
    -H "X-Request-ID: regression-rate-headers" \
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

limit_ok=false
remaining_ok=false
reset_ok=false

echo "$rate_headers" | grep -qi "^x-ratelimit-limit:" && limit_ok=true
echo "$rate_headers" | grep -qi "^x-ratelimit-remaining:" && remaining_ok=true
echo "$rate_headers" | grep -qi "^x-ratelimit-reset:" && reset_ok=true

if $limit_ok && $remaining_ok && $reset_ok; then
    pass "Rate limit headers"
else
    fail "Rate limit headers"
    echo "$rate_headers"
fi

# ============================================================
# 7. REAL 429 RATE LIMIT
# ============================================================

print_header "7. REAL 429 RATE LIMIT"

echo "Expected:"
echo "  Requests 1-20 -> HTTP 200"
echo "  Request 21    -> HTTP 429"
echo

rate_pass=true

for i in $(seq 1 21); do

    status=$(curl -sS \
        -o /tmp/rate_limit_body \
        -w "%{http_code}" \
        -X POST \
        "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $RATE_TEST_API_KEY" \
        -H "X-Request-ID: regression-rate-$i" \
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

    echo "Request $(printf '%02d' "$i") -> HTTP $status"

    if [ "$i" -le 20 ]; then
        if [ "$status" != "200" ]; then
            rate_pass=false
        fi
    else
        if [ "$status" != "429" ]; then
            rate_pass=false
        fi
    fi

done

if $rate_pass; then
    pass "Real 429 rate limiting"
else
    fail "Real 429 rate limiting"
fi

echo
echo "429 body:"
cat /tmp/rate_limit_body
echo

if grep -q '"rate_limit_error"' /tmp/rate_limit_body &&
   grep -q '"rate_limit_exceeded"' /tmp/rate_limit_body; then
    pass "429 JSON error body"
else
    fail "429 JSON error body"
fi

# ============================================================
# 8. BACKEND DOWN - NON STREAM
# ============================================================

print_header "8. BACKEND DOWN - NON-STREAM"

docker compose stop llm-backend >/dev/null

sleep 2

down_response=$(curl -sS \
    -o /tmp/backend_down_nonstream_body \
    -w "%{http_code}" \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -H "X-Request-ID: regression-backend-down-nonstream" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Say hello."
            }
        ],
        "stream": false,
        "max_tokens": 5
    }')

echo "HTTP status: $down_response"
cat /tmp/backend_down_nonstream_body
echo

if [ "$down_response" = "502" ] &&
   grep -q "Unable to connect to LLM backend" \
       /tmp/backend_down_nonstream_body; then

    pass "Backend down non-stream -> 502"
else
    fail "Backend down non-stream -> 502"
fi

# ============================================================
# 9. BACKEND DOWN - STREAMING
# ============================================================

print_header "9. BACKEND DOWN - STREAMING"

stream_down_status=$(curl -sS \
    -o /tmp/backend_down_stream_body \
    -w "%{http_code}" \
    -N \
    -X POST \
    "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -H "X-Request-ID: regression-backend-down-stream" \
    -d '{
        "model": "qwen-local",
        "messages": [
            {
                "role": "user",
                "content": "Say hello."
            }
        ],
        "stream": true,
        "max_tokens": 5
    }')

echo "HTTP status: $stream_down_status"
cat /tmp/backend_down_stream_body
echo

if [ "$stream_down_status" = "502" ] &&
   grep -q "Unable to connect to LLM backend" \
       /tmp/backend_down_stream_body; then

    pass "Backend down streaming -> 502"
else
    fail "Backend down streaming -> 502"
fi

# ============================================================
# 10. BACKEND RECOVERY
# ============================================================

print_header "10. BACKEND RECOVERY"

docker compose start llm-backend >/dev/null

until [ "$(docker inspect -f '{{.State.Health.Status}}' llm-backend 2>/dev/null)" = "healthy" ]; do
    echo "Backend status: $(docker inspect -f '{{.State.Health.Status}}' llm-backend 2>/dev/null)"
    sleep 2
done

backend_status=$(curl -sS -o /dev/null -w "%{http_code}" \
    "http://localhost:8081/health")

if [ "$backend_status" = "200" ]; then
    pass "Backend recovery"
else
    fail "Backend recovery"
fi

# ============================================================
# 11. POST-RECOVERY STREAMING
# ============================================================

print_header "11. POST-RECOVERY STREAMING"

recovery_stream=$(chat_request \
    "$API_KEY" \
    "regression-post-recovery" \
    "true")

if echo "$recovery_stream" | grep -q '^data:' &&
   echo "$recovery_stream" | grep -q 'data: \[DONE\]'; then

    pass "Streaming after backend recovery"
else
    fail "Streaming after backend recovery"
    echo "$recovery_stream"
fi

# ============================================================
# 12. PYTHON SYNTAX CHECK
# ============================================================

print_header "12. PYTHON SYNTAX CHECK"

if python3 -m py_compile app/main.py; then
    pass "app/main.py syntax"
else
    fail "app/main.py syntax"
fi

# ============================================================
# 13. STRUCTURAL CHECKS
# ============================================================

print_header "13. STRUCTURAL CHECKS"

checks_passed=true

grep -q "StreamingResponse" app/main.py || checks_passed=false
grep -q "HTTPException" app/main.py || checks_passed=false
grep -q "X-Request-ID" app/main.py || checks_passed=false
grep -q "X-RateLimit-Limit" app/main.py || checks_passed=false
grep -q "X-RateLimit-Remaining" app/main.py || checks_passed=false
grep -q "X-RateLimit-Reset" app/main.py || checks_passed=false
grep -q "rate_limit_exceeded" app/main.py || checks_passed=false
grep -q "data: \[DONE\]" app/main.py || checks_passed=false

if $checks_passed; then
    pass "Gateway structural checks"
else
    fail "Gateway structural checks"
fi

# ============================================================
# 14. ADVANCED RELIABILITY TESTS
# ============================================================

print_header "14. ADVANCED RELIABILITY TESTS"

# ------------------------------------------------------------
# 14A. MID-STREAM DISCONNECT
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "14A. MID-STREAM DISCONNECT"
echo "------------------------------------------------------------"

if docker inspect llm-fault-proxy >/dev/null 2>&1; then

    echo "Fault proxy found."

    # Make sure proxy is running.
    docker start llm-fault-proxy >/dev/null 2>&1 || true

    # Switch gateway to fault proxy.
    python3 - <<'PY2'
from pathlib import Path

path = Path(".env")
text = path.read_text()

lines = [
    line
    for line in text.splitlines()
    if not line.startswith("LLM_BACKEND_URL=")
]

lines.append("LLM_BACKEND_URL=http://llm-fault-proxy:18080")

path.write_text("\n".join(lines) + "\n")
PY2

    docker compose up -d --force-recreate gateway >/dev/null

    # Wait for gateway.
    for _ in $(seq 1 30); do
        if [ "$(docker inspect -f '{{.State.Health.Status}}' llm-gateway 2>/dev/null)" = "healthy" ]; then
            break
        fi
        sleep 2
    done

    midstream_output=$(curl -sS -N \
        --max-time 20 \
        -X POST \
        "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -H "X-Request-ID: regression-midstream-disconnect" \
        -d '{
            "model": "qwen-local",
            "messages": [
                {
                    "role": "user",
                    "content": "Write a long explanation about artificial intelligence, machine learning, neural networks, and their applications."
                }
            ],
            "stream": true,
            "max_tokens": 100
        }' 2>/dev/null || true)

    event_count=$(printf '%s\n' "$midstream_output" | grep -c '^data:' || true)

    echo "Received SSE events: $event_count"

    if [ "$event_count" -ge 3 ] &&
       ! printf '%s\n' "$midstream_output" | grep -q 'data: \[DONE\]'; then

        pass "Mid-stream disconnect detected"

    else
        fail "Mid-stream disconnect detection"
        printf '%s\n' "$midstream_output"
    fi

else
    fail "Mid-stream disconnect — fault proxy not found"
fi


# ------------------------------------------------------------
# 14B. REAL BACKEND TIMEOUT
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "14B. REAL BACKEND TIMEOUT"
echo "------------------------------------------------------------"

if docker inspect llm-fault-proxy >/dev/null 2>&1; then

    # Configure proxy to delay backend response.
    docker start llm-fault-proxy >/dev/null 2>&1 || true

    python3 - <<'PY2'
from pathlib import Path

path = Path(".env")
text = path.read_text()

lines = []

for line in text.splitlines():
    if line.startswith("LLM_BACKEND_URL="):
        if not any(x.startswith("LLM_BACKEND_URL=") for x in lines):
            lines.append("LLM_BACKEND_URL=http://llm-fault-proxy:18080")
    elif line.startswith("BACKEND_READ_TIMEOUT="):
        lines.append("BACKEND_READ_TIMEOUT=3")
    else:
        lines.append(line)

if not any(x.startswith("LLM_BACKEND_URL=") for x in lines):
    lines.append("LLM_BACKEND_URL=http://llm-fault-proxy:18080")

if not any(x.startswith("BACKEND_READ_TIMEOUT=") for x in lines):
    lines.append("BACKEND_READ_TIMEOUT=3")

path.write_text("\n".join(lines) + "\n")
PY2

    docker compose up -d --force-recreate gateway >/dev/null

    for _ in $(seq 1 30); do
        if [ "$(docker inspect -f '{{.State.Health.Status}}' llm-gateway 2>/dev/null)" = "healthy" ]; then
            break
        fi
        sleep 2
    done

    timeout_start=$(date +%s)

    timeout_status=$(curl -sS \
        --max-time 15 \
        -o /tmp/backend_timeout_body \
        -w "%{http_code}" \
        -X POST \
        "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -H "X-Request-ID: regression-backend-timeout" \
        -d '{
            "model": "qwen-local",
            "messages": [
                {
                    "role": "user",
                    "content": "Say hello."
                }
            ],
            "stream": false,
            "max_tokens": 5
        }' 2>/dev/null || true)

    timeout_end=$(date +%s)
    timeout_elapsed=$((timeout_end - timeout_start))

    echo "HTTP status: $timeout_status"
    echo "Elapsed: ${timeout_elapsed}s"

    cat /tmp/backend_timeout_body
    echo

    if [ "$timeout_status" = "502" ] &&
       grep -q "LLM backend request timed out" \
           /tmp/backend_timeout_body &&
       [ "$timeout_elapsed" -ge 2 ] &&
       [ "$timeout_elapsed" -le 8 ]; then

        pass "Real backend timeout -> 502"

    else
        fail "Real backend timeout -> 502"
    fi

else
    fail "Real backend timeout — fault proxy not found"
fi


# ------------------------------------------------------------
# 14C. RESTORE REAL BACKEND BEFORE CONCURRENT TEST
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "14C. RESTORE REAL BACKEND"
echo "------------------------------------------------------------"

cp "$ORIGINAL_ENV_BACKUP" .env

docker compose up -d --force-recreate gateway >/dev/null

for _ in $(seq 1 30); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' llm-gateway 2>/dev/null)" = "healthy" ]; then
        break
    fi
    sleep 2
done

echo "Real backend configuration restored."

# ------------------------------------------------------------
# 14D. CONCURRENT REQUESTS
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "14D. CONCURRENT REQUESTS"
echo "------------------------------------------------------------"

TOTAL_CONCURRENT=20
CONCURRENT_TMP=$(mktemp -d)

concurrent_start=$(date +%s)

for i in $(seq 1 "$TOTAL_CONCURRENT"); do

    (
        status=$(curl -sS \
            -o "$CONCURRENT_TMP/body-$i" \
            -w "%{http_code}" \
            --max-time 90 \
            -X POST \
            "$BASE_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $API_KEY" \
            -H "X-Request-ID: concurrent-regression-$i" \
            -d '{
                "model": "qwen-local",
                "messages": [
                    {
                        "role": "user",
                        "content": "Say hello."
                    }
                ],
                "stream": false,
                "max_tokens": 5
            }' 2>/dev/null || true)

        echo "$status" > "$CONCURRENT_TMP/status-$i"

    ) &

done

wait

concurrent_end=$(date +%s)
concurrent_elapsed=$((concurrent_end - concurrent_start))

concurrent_pass=0
concurrent_fail=0

for i in $(seq 1 "$TOTAL_CONCURRENT"); do

    status=$(cat "$CONCURRENT_TMP/status-$i" 2>/dev/null || echo "000")

    if [ "$status" = "200" ]; then
        concurrent_pass=$((concurrent_pass + 1))
    else
        concurrent_fail=$((concurrent_fail + 1))
        echo "Concurrent request $i -> HTTP $status"
    fi

done

rm -rf "$CONCURRENT_TMP"

echo "Concurrent requests: $TOTAL_CONCURRENT"
echo "Successful: $concurrent_pass"
echo "Failed: $concurrent_fail"
echo "Elapsed: ${concurrent_elapsed}s"

if [ "$concurrent_pass" -eq "$TOTAL_CONCURRENT" ]; then
    pass "Concurrent requests"
else
    fail "Concurrent requests"
fi


# ------------------------------------------------------------
# 14E. FINAL HEALTH CHECK
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "14E. FINAL HEALTH CHECK"
echo "------------------------------------------------------------"

for _ in $(seq 1 30); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' llm-gateway 2>/dev/null)" = "healthy" ]; then
        break
    fi
    sleep 2
done

final_gateway_health=$(curl -sS \
    -o /dev/null \
    -w "%{http_code}" \
    "$BASE_URL/health" 2>/dev/null || echo "000")

final_backend_health=$(curl -sS \
    -o /dev/null \
    -w "%{http_code}" \
    "http://localhost:8081/health" 2>/dev/null || echo "000")

echo "Gateway health: HTTP $final_gateway_health"
echo "Backend health: HTTP $final_backend_health"

if [ "$final_gateway_health" = "200" ] &&
   [ "$final_backend_health" = "200" ]; then

    pass "Environment restored and healthy"

else
    fail "Environment restoration"
fi

# FINAL SUMMARY
# ============================================================

print_header "FINAL REGRESSION SUMMARY"

echo "PASS : $PASS"
echo "FAIL : $FAIL"
echo "SKIP : $SKIP"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "============================================================"
    echo "REGRESSION RESULT: PASS"
    echo "============================================================"
else
    echo "============================================================"
    echo "REGRESSION RESULT: FAIL"
    echo "============================================================"
fi

echo
echo "Backend final status:"
docker inspect -f '{{.State.Health.Status}}' llm-backend 2>/dev/null || true

echo
echo "Gateway final status:"
docker inspect -f '{{.State.Health.Status}}' llm-gateway 2>/dev/null || true

rm -f /tmp/rate_limit_body
rm -f /tmp/backend_down_nonstream_body
rm -f /tmp/backend_down_stream_body

exit "$FAIL"
