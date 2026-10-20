#!/bin/bash
# Shared helpers for the live-endpoint pollers.
#
# Query probes go over GET (a safe method, so they are unaffected by whether
# CSRF is enforced yet). Mutation probes go over POST and carry a freshly primed
# CSRF token, which the stock (csrf_exempt) service ignores and the hardened
# service requires — so a mutation poll behaves correctly in both states.

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
GRAPHQL_URL="${GRAPHQL_URL:-${BASE_URL}/graphql/}"

# gql_get '<query string>' -> prints JSON response body
gql_get() {
  curl -fsS -G "$GRAPHQL_URL" --data-urlencode "query=$1" 2>/dev/null
}

# is_json_object '<body>' -> 0 if the body is a JSON object, else non-zero.
# Pollers call this before judging a response: an empty/garbled body (service
# down or restarting) must never be mistaken for a secure one. Note that
# `echo "" | jq -e '<cond>'` exits 0, so without this guard a dead endpoint
# would falsely report "secure".
is_json_object() {
  [ -n "$1" ] && printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1
}

# gql_post_token '<json body>' -> prints JSON response body.
# Primes a CSRF cookie from /api/csrf/ and sends both the cookie and the
# matching x-csrftoken header, so the request is accepted whether or not CSRF
# protection is currently enabled. Self-contained: the cookie jar never leaves
# this function (an earlier version lost it across a subshell).
gql_post_token() {
  local jar token
  jar="$(mktemp)"
  curl -s -c "$jar" "${BASE_URL}/api/csrf/" >/dev/null 2>&1
  token="$(awk '$6=="csrftoken"{print $7}' "$jar")"
  curl -fsS -b "$jar" -H "x-csrftoken: $token" \
    -H 'content-type: application/json' \
    -X POST "$GRAPHQL_URL" --data "$1" 2>/dev/null
  rm -f "$jar"
}
