#!/usr/bin/env bash
# #3 Development defaults — Strawberry serves the GraphiQL IDE to any browser
# that opens /graphql/, and sends resolver exceptions back to the client as-is.
set -euo pipefail
URL="http://127.0.0.1:8000/graphql/"

echo "Opening /graphql/ the way a browser does:"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'accept: text/html' "$URL"
echo "(200 = the IDE is served / vulnerable, 404 = switched off / fixed)"

echo "Looking up a post with a malformed ID and with a missing ID:"
for id in abc 999; do
  curl -fsS -G "$URL" --data-urlencode "query={ post(id: \"$id\") { title } }" \
    | jq -r '.errors[].message'
done
echo '(Django exception messages = vulnerable, "Unexpected error." = fixed)'
