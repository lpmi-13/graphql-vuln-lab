#!/bin/bash
# Shared helpers for the live-endpoint pollers.
#
# Query probes go over GET, which the POST rate limit (60/m per client address)
# ignores. Mutation probes go over POST and count against it.
#
# Every probe is sent from CHECK_SRC (127.0.0.2) rather than 127.0.0.1. The
# limiter keys on the client address, so the checker spends its own budget and
# never the learner's. The examiner retries a pending task every second, so
# pollers that POST also wait CHECK_DELAY seconds first to stay under the limit
# themselves. Set CHECK_SRC= to send from the default address.

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
GRAPHQL_URL="${GRAPHQL_URL:-${BASE_URL}/graphql/}"
CHECK_SRC="${CHECK_SRC-127.0.0.2}"
CHECK_DELAY="${CHECK_DELAY:-2}"

# check_curl <curl args...> -> runs curl from CHECK_SRC when it is set.
check_curl() {
  if [ -n "$CHECK_SRC" ]; then
    curl --interface "$CHECK_SRC" "$@"
  else
    curl "$@"
  fi
}

# gql_get '<query string>' -> prints JSON response body
gql_get() {
  check_curl -fsS -G "$GRAPHQL_URL" --data-urlencode "query=$1" 2>/dev/null
}

# is_json_object '<body>' -> 0 if the body is a JSON object, else non-zero.
# Pollers call this before judging a response: an empty/garbled body (service
# down or restarting) must never be mistaken for a secure one. Note that
# `echo "" | jq -e '<cond>'` exits 0, so without this guard a dead endpoint
# would falsely report "secure".
is_json_object() {
  [ -n "$1" ] && printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1
}

# gql_post '<json body>' -> prints JSON response body. A rate-limited (403)
# response prints nothing, so is_json_object rejects it.
gql_post() {
  check_curl -fsS -H 'content-type: application/json' \
    -X POST "$GRAPHQL_URL" --data "$1" 2>/dev/null
}

# pause_before_post -> wait CHECK_DELAY seconds (see above).
pause_before_post() {
  sleep "$CHECK_DELAY"
}
