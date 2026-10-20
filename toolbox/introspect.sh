#!/usr/bin/env bash
# #1 Introspection — dump the schema straight from the live endpoint.
# If introspection is enabled, this prints every type and field.
set -euo pipefail
URL="http://127.0.0.1:8000/graphql/"

curl -fsS -G "$URL" --data-urlencode \
  'query={__schema{queryType{name} types{name kind fields{name}}}}' | jq .
