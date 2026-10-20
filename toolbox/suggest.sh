#!/usr/bin/env bash
# #2 Field suggestions — a misspelled field makes the server suggest the real
# one ("Did you mean ...?"), leaking the schema even without introspection.
set -euo pipefail
URL="http://127.0.0.1:8000/graphql/"

echo "Asking for a bogus field 'usrs':"
curl -fsS -G "$URL" --data-urlencode 'query={ usrs { id } }' | jq -r '.errors[].message'
