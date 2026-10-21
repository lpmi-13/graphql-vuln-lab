#!/bin/bash
# PASS (exit 0) when a forged, tokenless POST is rejected (403) AND a request
# carrying a valid CSRF token still succeeds.
source "$(dirname "$0")/_common.sh"

MUT='{"query":"mutation{ updateBio(text:\"hello\"){ ok } }"}'

# 1. Forged request: no cookie, no token. Must be refused.
FORGED="$(curl -s -o /dev/null -w '%{http_code}' \
  -H 'content-type: application/json' \
  -X POST "$GRAPHQL_URL" --data "$MUT")"

# 2. Legitimate request: primed csrftoken cookie + matching header. Must work.
OK="$(gql_post_token "$MUT" | jq -r '.data.updateBio.ok' 2>/dev/null)"

if [ "$FORGED" = "403" ] && [ "$OK" = "true" ]; then
  echo "CSRF is enforced — forged POSTs are rejected, valid ones still work."
  exit 0
fi

echo "CSRF check failed (tokenless POST HTTP ${FORGED}; valid-token mutation ok=${OK:-missing})." >&2
exit 1
