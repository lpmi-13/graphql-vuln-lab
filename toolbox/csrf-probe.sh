#!/usr/bin/env bash
# #3 CSRF — a cross-site-style POST with no CSRF token. While the view is
# csrf_exempt this forged state-changing mutation is accepted (HTTP 200).
set -euo pipefail
URL="http://127.0.0.1:8000/graphql/"

echo "Forged POST (no CSRF token):"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST "$URL" \
  -H 'content-type: application/json' \
  -d '{"query":"mutation{ updateBio(text:\"owned\"){ ok } }"}'
echo "(200 = accepted / vulnerable, 403 = rejected / fixed)"
