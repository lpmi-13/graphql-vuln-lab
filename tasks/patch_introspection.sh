#!/bin/bash
# PASS (exit 0) when a full introspection query no longer returns the schema.
source "$(dirname "$0")/_common.sh"

BODY="$(gql_get '{__schema{types{name}}}' || true)"

if ! is_json_object "$BODY"; then
  echo "No valid response from the GraphQL endpoint." >&2
  exit 1
fi

if printf '%s' "$BODY" | jq -e '(.data.__schema == null) and ((.errors | length) > 0)' >/dev/null 2>&1; then
  echo "Introspection is disabled — the schema no longer leaks."
  exit 0
fi

echo "Introspection still returns the schema." >&2
exit 1
