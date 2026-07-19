#!/bin/sh
set -e

: "${STS_URL:=http://127.0.0.1:8080/realms/obo-demo/protocol/openid-connect/token}"
: "${RESOURCE_SERVER_URL:=http://resource-server:9002/}"
: "${HUMAN_USERNAME:?must be set}"
: "${HUMAN_PASSWORD:?must be set}"
: "${CLIENT_ID:?must be set}"
: "${CLIENT_SECRET:?must be set}"
: "${EXPECTED_ACTOR_SPIFFE_ID:?must be set}"

b64url_decode() {
    # JWT segments are base64url without padding; pad and swap the alphabet
    # back to standard base64 before decoding.
    input="$1"
    remainder=$((${#input} % 4))
    if [ "$remainder" -eq 2 ]; then input="${input}=="; fi
    if [ "$remainder" -eq 3 ]; then input="${input}="; fi
    echo "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

echo "Waiting for the Envoy sidecar's mTLS connection to the STS to come up..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null "http://127.0.0.1:8080/realms/obo-demo/.well-known/openid-configuration"; then
        break
    fi
    sleep 1
done

echo "== [1/3] Logging in as ${HUMAN_USERNAME} (simulated human login, ROPC grant) =="
LOGIN_RESPONSE=$(curl -s -X POST "$STS_URL" \
    -d "grant_type=password" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "username=${HUMAN_USERNAME}" \
    -d "password=${HUMAN_PASSWORD}")

SUBJECT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // empty')
if [ -z "$SUBJECT_TOKEN" ]; then
    echo "Login failed: $LOGIN_RESPONSE"
    exit 1
fi
echo "subject_token sub:   $(b64url_decode "$(echo "$SUBJECT_TOKEN" | cut -d. -f2)" | jq -c '{sub, act}')"

echo "== [2/3] Exchanging the human's token, authenticated as the ${CLIENT_ID} workload (RFC 8693 token-exchange, self-exchange) =="
EXCHANGE_RESPONSE=$(curl -s -X POST "$STS_URL" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
    -d "subject_token=${SUBJECT_TOKEN}" \
    -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}")

EXCHANGED_TOKEN=$(echo "$EXCHANGE_RESPONSE" | jq -r '.access_token // empty')
if [ -z "$EXCHANGED_TOKEN" ]; then
    echo "Token exchange failed: $EXCHANGE_RESPONSE"
    exit 1
fi
EXCHANGED_CLAIMS=$(b64url_decode "$(echo "$EXCHANGED_TOKEN" | cut -d. -f2)")
echo "exchanged token claims: $(echo "$EXCHANGED_CLAIMS" | jq -c '{sub, act}')"

ACTOR_SPIFFE_ID=$(echo "$EXCHANGED_CLAIMS" | jq -r '.act.sub // empty')
if [ "$ACTOR_SPIFFE_ID" != "$EXPECTED_ACTOR_SPIFFE_ID" ]; then
    echo "FAIL: expected act.sub=${EXPECTED_ACTOR_SPIFFE_ID}, got '${ACTOR_SPIFFE_ID}'"
    exit 1
fi
SUBJECT=$(echo "$EXCHANGED_CLAIMS" | jq -r '.sub // empty')

echo "== [3/3] Calling the resource server with the exchanged token =="
HEADERS=$(curl -s -D - -o /tmp/body "$RESOURCE_SERVER_URL" -H "Authorization: Bearer ${EXCHANGED_TOKEN}")
echo "$HEADERS" | grep -i "^HTTP\|x-jwt-payload"

PAYLOAD_HEADER=$(echo "$HEADERS" | grep -i "^x-jwt-payload:" | sed 's/^[Xx]-[Jj]wt-[Pp]ayload: *//' | tr -d '\r')
if [ -z "$PAYLOAD_HEADER" ]; then
    echo "FAIL: resource server did not return a verified x-jwt-payload header (token rejected?)"
    exit 1
fi
RESOURCE_SERVER_CLAIMS=$(b64url_decode "$PAYLOAD_HEADER")
echo "resource-server verified claims: $(echo "$RESOURCE_SERVER_CLAIMS" | jq -c '{sub, act}')"

RS_ACT=$(echo "$RESOURCE_SERVER_CLAIMS" | jq -r '.act.sub // empty')
RS_SUB=$(echo "$RESOURCE_SERVER_CLAIMS" | jq -r '.sub // empty')
if [ "$RS_ACT" != "$EXPECTED_ACTOR_SPIFFE_ID" ] || [ "$RS_SUB" != "$SUBJECT" ]; then
    echo "FAIL: resource-server-observed claims do not match the exchanged token"
    exit 1
fi

echo "SUCCESS: human sub '${SUBJECT}' preserved end to end, acting workload recorded as '${RS_ACT}', cryptographically verified by the resource server."
