#!/usr/bin/env bash
# Prints an HS256 access token allowed to publish and subscribe to every topic,
# valid for one hour. For the integration tests only.
#
# Usage: tool/test_jwt.sh <key> <issuer> <audience>
set -euo pipefail

key=$1 issuer=$2 audience=$3
now=$(date +%s)

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Mercure 1.x hubs only accept RFC 9068 access tokens whose grants are RFC 9396
# authorization details.
header=$(printf '{"alg":"HS256","typ":"at+jwt"}' | b64url)
payload=$(
  printf '{"iss":"%s","aud":"%s","sub":"%s","client_id":"%s","iat":%d,"exp":%d,"jti":"%s",' \
    "$issuer" "$audience" dart_mercure-tests dart_mercure-tests "$now" "$((now + 3600))" "$now-$$"
  printf '"authorization_details":[{"type":"https://mercure.rocks/authorization-detail",'
  printf '"actions":["publish","subscribe"],"topics":[{"match":"*"}]}]}'
)
claims=$(printf '%s' "$payload" | b64url)
signature=$(printf '%s.%s' "$header" "$claims" |
  openssl dgst -sha256 -hmac "$key" -binary | b64url)

printf '%s.%s.%s\n' "$header" "$claims" "$signature"
