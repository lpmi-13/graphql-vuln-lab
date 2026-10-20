#!/bin/bash
# PASS (exit 0) when a deeply nested query is rejected, while a shallow query
# still works.
source "$(dirname "$0")/_common.sh"

DEEP='{ me{ posts{ author{ posts{ author{ posts{ id }}}}}} }'
SHALLOW='{ me{ username posts{ title } } }'

DEEP_BODY="$(gql_get "$DEEP" || true)"
if ! is_json_object "$DEEP_BODY"; then
  echo "No valid response to the deep query." >&2
  exit 1
fi
if ! printf '%s' "$DEEP_BODY" | jq -e '(.errors | length) > 0' >/dev/null 2>&1; then
  echo "A deeply nested query still executed." >&2
  exit 1
fi

SHALLOW_BODY="$(gql_get "$SHALLOW" || true)"
if ! is_json_object "$SHALLOW_BODY"; then
  echo "No valid response to the shallow query." >&2
  exit 1
fi
if ! printf '%s' "$SHALLOW_BODY" | jq -e '(.data.me != null) and (((.errors // []) | length) == 0)' >/dev/null 2>&1; then
  echo "The depth limit also rejected a normal shallow query." >&2
  exit 1
fi

echo "Query depth is capped — deep queries are rejected, shallow ones work."
exit 0
