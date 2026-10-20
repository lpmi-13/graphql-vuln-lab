#!/bin/bash
# Readiness probe: succeeds once the GraphQL endpoint answers a trivial query
# twice in a row. Uses GET so it is unaffected by whether CSRF is enforced.
source "$(dirname "$0")/_common.sh"

hits=0
for _ in $(seq 1 120); do
  if gql_get '{__typename}' | jq -e '.data.__typename == "Query"' >/dev/null 2>&1; then
    hits=$((hits + 1))
    [ "$hits" -ge 2 ] && { echo "GraphQL endpoint is ready."; exit 0; }
  else
    hits=0
  fi
  sleep 1
done

echo "GraphQL backend did not become ready in time." >&2
exit 1
