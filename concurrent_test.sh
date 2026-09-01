#!/usr/bin/env bash

set -u

BASE_URL="http://localhost:8000"
API_KEY="${API_KEY:?API_KEY environment variable is required}"

TOTAL=20

TMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

echo
echo "============================================================"
echo "CONCURRENT REQUEST TEST"
echo "============================================================"
echo
echo "Total concurrent requests: $TOTAL"
echo "API key: $API_KEY"
echo

START=$(date +%s%3N)

for i in $(seq 1 "$TOTAL"); do

    (
        REQUEST_ID="concurrent-test-$i"

        body=$(curl -sS \
            --max-time 60 \
            -X POST \
            "$BASE_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $API_KEY" \
            -H "X-Request-ID: $REQUEST_ID" \
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
            }' \
            -w '\n%{http_code}')

        status=$(printf '%s\n' "$body" | tail -n1)
        response=$(printf '%s\n' "$body" | sed '$d')

        {
            echo "REQUEST_ID=$REQUEST_ID"
            echo "STATUS=$status"
            echo "BODY=$response"
        } > "$TMP_DIR/$i"

    ) &

done

wait

END=$(date +%s%3N)

DURATION=$((END - START))

echo "All concurrent requests completed."
echo "Elapsed: ${DURATION} ms"
echo

PASS=0
FAIL=0

for i in $(seq 1 "$TOTAL"); do

    file="$TMP_DIR/$i"

    request_id=$(grep '^REQUEST_ID=' "$file" | cut -d= -f2-)
    status=$(grep '^STATUS=' "$file" | cut -d= -f2-)

    printf "Request %02d -> HTTP %s -> %s\n" \
        "$i" \
        "$status" \
        "$request_id"

    if [ "$status" = "200" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

done

echo
echo "============================================================"
echo "CONCURRENT SUMMARY"
echo "============================================================"

echo "PASS : $PASS"
echo "FAIL : $FAIL"

echo
echo "============================================================"
echo "GATEWAY HEALTH"
echo "============================================================"

curl -sS "$BASE_URL/health"

echo
echo

echo "============================================================"
echo "BACKEND HEALTH"
echo "============================================================"

curl -sS http://localhost:8081/health

echo
echo

if [ "$FAIL" -eq 0 ]; then
    echo "============================================================"
    echo "CONCURRENT RESULT: PASS"
    echo "============================================================"
    exit 0
else
    echo "============================================================"
    echo "CONCURRENT RESULT: FAIL"
    echo "============================================================"
    exit 1
fi
