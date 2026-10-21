#!/bin/bash
# Local validation harness / release gate.
#
# Boots the app in several configurations and asserts that each hardening
# control flips exactly its own graded poll from fail -> pass, that no control
# flips another's poll (orthogonality), and that the fully hardened build passes
# all five while legitimate requests keep working. It also checks the depth
# limits the lesson allows, and that the pollers' POSTs do not use up the
# learner's rate-limit budget.
#
# Env overrides:
#   PYTHON   python interpreter with the app's deps (default: python3)
#   UVICORN  uvicorn entrypoint             (default: uvicorn)
#   CHECK_SRC  address the pollers send from (default: 127.0.0.2; empty
#              sends from the default address and skips the rate-limit test)
set -u

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HARNESS_DIR/.." && pwd)"
APP="$REPO/app"
TASKS="$REPO/tasks"
PKG="$APP/graphql_lab"

PYTHON="${PYTHON:-python3}"
UVICORN="${UVICORN:-uvicorn}"
PORT=""  # chosen fresh per server start, below

TECHS=(introspection field_suggestions dev_defaults alias_limit depth_limit)

# The pollers pause before POSTing to stay under the rate limit when the
# examiner retries them every second; the harness polls each one only once.
export CHECK_DELAY=0
export CHECK_SRC="${CHECK_SRC-127.0.0.2}"

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
# apply_config "<schema flags>" "<ide: on|off>"
apply_config() {
  "$PYTHON" "$HARNESS_DIR/gen_schema.py" $1 > "$PKG/schema.py"
  if [ "$2" = "off" ]; then
    cp "$HARNESS_DIR/solution/urls.py" "$PKG/urls.py"   # graphql_ide=None
  else
    cp "$HARNESS_DIR/fixtures/urls_vuln.py" "$PKG/urls.py"
  fi
}

# poll <tech> -> 0 if the endpoint is SECURE for that technique
poll() { bash "$TASKS/patch_${1}.sh" >/dev/null 2>&1; }

# assert_all <tech that should be secure>... -> every other tech should be vuln
assert_all() {
  local t s want
  for t in "${TECHS[@]}"; do
    want=vuln
    for s in "$@"; do [ "$t" = "$s" ] && want=secure; done
    assert "$t" "$want"
  done
}

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
assert_all
stop_server

# Per-technique isolation: each control flips only its own poll.
declare -A FLAG_FOR=(
  [introspection]="introspection"
  [field_suggestions]="suggestions"
  [alias_limit]="alias"
  [depth_limit]="depth"
)
for target in introspection field_suggestions alias_limit depth_limit; do
  say "Only '${target}' hardened (IDE still on, errors unmasked)"
  apply_config "${FLAG_FOR[$target]}" on
  start_server
  assert_all "$target"
  stop_server
done

say "Only 'dev_defaults' hardened (IDE off, resolver errors masked)"
apply_config "mask" off
start_server
assert_all dev_defaults
stop_server

say "Half of 'dev_defaults': resolver errors masked, IDE still on"
apply_config "mask" on
start_server
assert_all
stop_server

say "Half of 'dev_defaults': IDE off, errors unmasked"
apply_config "" off
start_server
assert_all
stop_server

# MaskErrors' default also masks validation errors, which hides "Did you
# mean" as a side effect; the dev_defaults poll must not accept it.
say "Over-masked: IDE off, MaskErrors() masking every error"
apply_config "mask=all" off
start_server
assert_all field_suggestions
stop_server

# Strawberry's depth excludes the leaf field: the probe is depth 6 and the
# post page depth 3. The lesson's answer is 3 (covered above); the check also
# accepts headroom up to 5, but not 2 (breaks the post page) or 6 (lets the
# probe through).
for depth in 2 5 6; do
  if [ "$depth" = 5 ]; then want=secure; else want=vuln; fi
  say "Depth boundary: max_depth=${depth}"
  apply_config "depth=${depth}" on
  start_server
  assert depth_limit "$want"
  stop_server
done

say "Fully hardened: all five pass"
apply_config "introspection suggestions mask alias depth" off
start_server
assert_all "${TECHS[@]}"
# Each poller also asserts a legitimate request still works, so a green
# "secure" here already means normal traffic is unaffected.

if [ -n "$CHECK_SRC" ]; then
  say "Checker POSTs leave the learner's rate-limit budget alone"
  # Poll until the checker's own budget is spent. The limiter uses fixed
  # 60-second windows, so a fixed number of polls can straddle a reset.
  MUT='{"query":"mutation{ verifyOtp(code:\"0000\"){ ok } }"}'
  for _ in $(seq 1 60); do
    poll alias_limit
    checker_code="$(curl -s -o /dev/null -w '%{http_code}' --interface "$CHECK_SRC" \
      -H 'content-type: application/json' -X POST "$GRAPHQL_URL" --data "$MUT")"
    [ "$checker_code" = "403" ] && break
  done
  learner_code="$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'content-type: application/json' -X POST "$GRAPHQL_URL" --data "$MUT")"
  if [ "$checker_code" = "403" ]; then
    ok "checker exhausted its own budget (HTTP 403 from ${CHECK_SRC})"
  else
    bad "checker POST from ${CHECK_SRC}: expected 403, got ${checker_code}"
  fi
  if [ "$learner_code" = "200" ]; then
    ok "learner POST from 127.0.0.1 still accepted"
  else
    bad "learner POST from 127.0.0.1: expected 200, got ${learner_code}"
  fi
fi
stop_server

say "Summary"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
