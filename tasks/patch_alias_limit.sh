#!/bin/bash
# PASS (exit 0) when one request packed with many aliased verifyOtp mutations
# is rejected, while a single mutation is still allowed.
source "$(dirname "$0")/_common.sh"

# 60 aliased OTP attempts smuggled into a single HTTP request.
MANY="$(python3 -c 'print("mutation{" + " ".join(f"a{i}: verifyOtp(code:\"{i:04d}\"){{ ok }}" for i in range(60)) + "}")')"
MANY_BODY="$(jq -nc --arg q "$MANY" '{query:$q}')"

pause_before_post
ABUSE="$(gql_post "$MANY_BODY" || true)"
if ! is_json_object "$ABUSE"; then
  echo "No valid response to the packed request." >&2
  exit 1
fi

# The packed request must now fail validation (errors present, no data).
if ! printf '%s' "$ABUSE" | jq -e '((.errors | length) > 0) and (.data == null)' >/dev/null 2>&1; then
  echo "A request with 60 aliased mutations still executed." >&2
  exit 1
fi

# A legitimate single mutation must still work.
ONE="$(gql_post '{"query":"mutation{ verifyOtp(code:\"0000\"){ ok } }"}' || true)"
if ! is_json_object "$ONE" || [ "$(printf '%s' "$ONE" | jq -r '.data.verifyOtp.ok')" != "true" ]; then
  echo "The alias cap also broke a normal single mutation." >&2
  exit 1
fi

echo "Alias abuse is capped — packed requests are rejected, normal ones work."
exit 0
