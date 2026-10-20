#!/bin/bash
# PASS (exit 0) when a misspelled-field error no longer suggests a real field.
source "$(dirname "$0")/_common.sh"

# 'usrs' is a misspelling of the real 'users' field.
BODY="$(gql_get '{ usrs { id } }' || true)"

if ! is_json_object "$BODY"; then
  echo "No valid response from the GraphQL endpoint." >&2
  exit 1
fi

# The query must still be rejected (the field is bogus) ...
if ! printf '%s' "$BODY" | jq -e '(.errors | length) > 0' >/dev/null 2>&1; then
  echo "Expected a validation error for the bogus field, got none." >&2
  exit 1
fi

# ... but the error must not reveal the real field name.
if printf '%s' "$BODY" | jq -r '.errors[].message' | grep -qi 'did you mean'; then
  echo "Field suggestions still leak real field names." >&2
  exit 1
fi

echo "Field suggestions are disabled — errors no longer name real fields."
exit 0
