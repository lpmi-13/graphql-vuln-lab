#!/bin/bash
# Local validation harness / release gate.
#
# Boots the app in several configurations and asserts that each hardening
# control flips exactly its own graded poll from fail -> pass, that no control
# flips another's poll (orthogonality), and that the fully hardened build passes
# all five while legitimate requests keep working.
#
# Env overrides:
#   PYTHON   python interpreter with the app's deps (default: python3)
#   UVICORN  uvicorn entrypoint             (default: uvicorn)
#   PORT     listen port                    (default: 8000)
set -u

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HARNESS_DIR/.." && pwd)"
APP="$REPO/app"
TASKS="$REPO/tasks"
PKG="$APP/graphql_lab"

PYTHON="${PYTHON:-python3}"
UVICORN="${UVICORN:-uvicorn}"
PORT=""  # chosen fresh per server start, below

TECHS=(introspection field_suggestions csrf alias_limit depth_limit)
SERVER_PID=""
PASS=0
FAIL=0

say()  { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

# --- server lifecycle ---------------------------------------------------------
# A fresh ephemeral port for every start, so no restart can ever collide with a
# still-dying previous server and leave the old config serving.
pick_port() {
  "$PYTHON" - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

stop_server() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1
    for _ in $(seq 1 20); do
      kill -0 "$SERVER_PID" >/dev/null 2>&1 || break
      sleep 0.2
    done
  fi
  SERVER_PID=""
}

start_server() {
  PORT="$(pick_port)"
  export BASE_URL="http://127.0.0.1:${PORT}"
  export GRAPHQL_URL="${BASE_URL}/graphql/"
  ( cd "$APP" && exec "$UVICORN" graphql_lab.asgi:application \
      --host 127.0.0.1 --port "$PORT" ) >/tmp/gql-harness.log 2>&1 &
  SERVER_PID=$!
  bash "$TASKS/wait_ready.sh" >/dev/null 2>&1
}

# --- config application -------------------------------------------------------
# apply_config "<schema flags>" "<csrf: on|off>"
apply_config() {
  "$PYTHON" "$HARNESS_DIR/gen_schema.py" $1 > "$PKG/schema.py"
  if [ "$2" = "off" ]; then
    cp "$HARNESS_DIR/solution/urls.py" "$PKG/urls.py"   # csrf_exempt removed
  else
    cp "$HARNESS_DIR/fixtures/urls_vuln.py" "$PKG/urls.py"
  fi
  if echo "$1" | grep -qw alias; then
    cp "$HARNESS_DIR/solution/validation.py" "$PKG/validation.py"
  else
    rm -f "$PKG/validation.py"
  fi
}

# poll <tech> -> 0 if the endpoint is SECURE for that technique
poll() { bash "$TASKS/patch_${1}.sh" >/dev/null 2>&1; }

# assert <tech> <secure|vuln>
assert() {
  local tech="$1" want="$2"
  if poll "$tech"; then got=secure; else got=vuln; fi
  if [ "$got" = "$want" ]; then
    ok "$tech is $want"
  else
    bad "$tech: expected $want, got $got"
  fi
}

restore_pristine() {
  cp "$HARNESS_DIR/fixtures/schema_vuln.py" "$PKG/schema.py"
  cp "$HARNESS_DIR/fixtures/urls_vuln.py" "$PKG/urls.py"
  rm -f "$PKG/validation.py"
}

cleanup() { stop_server; restore_pristine; }
trap cleanup EXIT

# Snapshot the committed (pristine) files so we always restore them.
cp "$PKG/schema.py" "$HARNESS_DIR/fixtures/schema_vuln.py"
cp "$PKG/urls.py" "$HARNESS_DIR/fixtures/urls_vuln.py"

# -----------------------------------------------------------------------------
say "Baseline: stock defaults are vulnerable on all five"
apply_config "" on
start_server
for t in "${TECHS[@]}"; do assert "$t" vuln; done
BIO_BEFORE="$(curl -fsS -G "$GRAPHQL_URL" \
  --data-urlencode 'query={ me { bio } }' | jq -r '.data.me.bio')"
poll csrf  # The vulnerable check fails, but its valid-token probe still runs.
BIO_AFTER="$(curl -fsS -G "$GRAPHQL_URL" \
  --data-urlencode 'query={ me { bio } }' | jq -r '.data.me.bio')"
if [ -n "$BIO_BEFORE" ] && [ "$BIO_BEFORE" != "null" ] && [ "$BIO_BEFORE" = "$BIO_AFTER" ]; then
  ok "csrf poll preserves the profile bio"
else
  bad "csrf poll changed the profile bio"
fi
stop_server

# Per-technique isolation: each control flips only its own poll.
declare -A FLAG_FOR=(
  [introspection]="introspection"
  [field_suggestions]="suggestions"
  [alias_limit]="alias"
  [depth_limit]="depth"
)
for target in introspection field_suggestions alias_limit depth_limit; do
  say "Only '${target}' hardened (CSRF still exempt)"
  apply_config "${FLAG_FOR[$target]}" on
  start_server
  for t in "${TECHS[@]}"; do
    if [ "$t" = "$target" ]; then assert "$t" secure; else assert "$t" vuln; fi
  done
  stop_server
done

say "Only 'csrf' hardened (schema still stock)"
apply_config "" off
start_server
for t in "${TECHS[@]}"; do
  if [ "$t" = "csrf" ]; then assert "$t" secure; else assert "$t" vuln; fi
done
stop_server

say "Fully hardened: all five pass"
apply_config "introspection suggestions alias depth" off
start_server
for t in "${TECHS[@]}"; do assert "$t" secure; done
# Each poller also asserts a legitimate request still works, so a green
# "secure" here already means normal traffic is unaffected.
stop_server

say "Summary"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
