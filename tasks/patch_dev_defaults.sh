#!/bin/bash
# PASS (exit 0) when the service no longer serves the GraphiQL IDE and no
# longer returns the text of exceptions raised inside resolvers, while GraphQL's
# own validation errors and ordinary lookups still come through. Reports every
# remaining problem, since the two fixes live in different files.
source "$(dirname "$0")/_common.sh"

status=0

# 1. A browser opening /graphql/ must not get the IDE. Strawberry answers 404
#    once the view's IDE is switched off.
IDE_STATUS="$(check_curl -s -o /dev/null -w '%{http_code}' -H 'accept: text/html' "$GRAPHQL_URL")"
if [ "$IDE_STATUS" = "000" ]; then
  echo "No response from the GraphQL endpoint." >&2
  exit 1
fi
if [ "$IDE_STATUS" = "200" ]; then
  echo "The endpoint still serves the GraphiQL IDE." >&2
  status=1
fi

# 2. A resolver exception must reach the client without Django's own wording.
BAD="$(gql_get '{ post(id: "abc") { title } }' || true)"
if ! is_json_object "$BAD" || ! printf '%s' "$BAD" | jq -e '(.errors | length) > 0' >/dev/null 2>&1; then
  echo "No error response to a post lookup with a malformed ID." >&2
  exit 1
fi
if printf '%s' "$BAD" | jq -r '.errors[].message' | grep -qi 'expected a number'; then
  echo "Resolver errors still expose Django's exception messages." >&2
  status=1
fi

# 3. Masking must stop at resolver errors: a misspelled field still gets
#    GraphQL's own validation message.
TYPO="$(gql_get '{ usrs { id } }' || true)"
if ! printf '%s' "$TYPO" | jq -r '.errors[].message' 2>/dev/null | grep -q 'Cannot query field'; then
  echo "Validation errors are masked too; mask only errors raised in resolvers." >&2
  status=1
fi

# 4. A lookup with a real ID must still work.
ID="$(gql_get '{ posts { id } }' | jq -r '.data.posts[0].id // empty' 2>/dev/null)"
TITLE="$(gql_get "{ post(id: \"${ID}\") { title } }" | jq -r '.data.post.title // empty' 2>/dev/null)"
if [ -z "$TITLE" ]; then
  echo "A normal post lookup no longer works." >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "Development defaults are off — no IDE, and resolver errors are masked."
fi
exit "$status"
