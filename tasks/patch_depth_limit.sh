#!/bin/bash
# PASS (exit 0) when a deeply nested query is rejected, while the app's deepest
# real query (a post page: the post, its author, and the author's other posts)
# still works. Strawberry's QueryDepthLimiter does not count the leaf field, so
# DEEP has depth 6 and the post page depth 3: max_depth 3-5 passes.
source "$(dirname "$0")/_common.sh"

DEEP='{ me{ posts{ author{ posts{ author{ posts{ id }}}}}} }'

DEEP_BODY="$(gql_get "$DEEP" || true)"
if ! is_json_object "$DEEP_BODY"; then
  echo "No valid response to the deep query." >&2
  exit 1
fi
if ! printf '%s' "$DEEP_BODY" | jq -e '(.errors | length) > 0' >/dev/null 2>&1; then
  echo "A deeply nested query still executed." >&2
  exit 1
fi

ID="$(gql_get '{ posts { id } }' | jq -r '.data.posts[0].id // empty' 2>/dev/null)"
POST_PAGE="{ post(id: \"${ID}\") { title author { username posts { title } } } }"

PAGE_BODY="$(gql_get "$POST_PAGE" || true)"
if ! is_json_object "$PAGE_BODY"; then
  echo "No valid response to the post-page query." >&2
  exit 1
fi
if ! printf '%s' "$PAGE_BODY" | jq -e '(.data.post != null) and (((.errors // []) | length) == 0)' >/dev/null 2>&1; then
  echo "The depth limit also rejected the depth-3 post-page query." >&2
  exit 1
fi

echo "Query depth is capped — deep queries are rejected, normal ones work."
exit 0
