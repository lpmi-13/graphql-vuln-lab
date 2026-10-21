# GraphQL Security Lab

An iximiuz Labs challenge: a stock **Django + Strawberry** GraphQL service that
ships with five classic weaknesses. The learner probes each one, hardens the
real project, and a live-polling check flips green. Based on Intigriti's
[Five easy ways to hack GraphQL targets](https://www.intigriti.com/researchers/blog/hacking-tools/five-easy-ways-to-hack-graphql-targets),
but not step for step: it keeps the introspection, field-suggestion and alias
techniques, uses nested-query depth instead of batching for the DoS, and
replaces the article's CSRF section (this API has no login for CSRF to abuse)
with two production-readiness checks.

## ▶ [Try it live on iximiuz Labs →](https://labs.iximiuz.com/challenges/graphql-vuln-lab-ca696b14)

**https://labs.iximiuz.com/challenges/graphql-vuln-lab-ca696b14**

## The five techniques

| # | Technique | Learner's change | File |
|---|-----------|------------------|------|
| 1 | Introspection enabled | add `DisableIntrospection()` extension | `schema.py` |
| 2 | Field suggestions ("Did you mean") | add `StrawberryConfig(disable_field_suggestions=True)` | `schema.py` |
| 3 | Development defaults: GraphiQL IDE served, resolver errors returned verbatim | `graphql_ide=None` on the view; `MaskErrors(should_mask_error=lambda error: error.original_error is not None)` | `urls.py`, `schema.py` |
| 4 | Alias-packing rate-limit bypass | **write** a custom alias-count validation rule | `schema.py` |
| 5 | Deep-query DoS | add `QueryDepthLimiter(max_depth=3)`, the depth of the app's deepest real query (the check accepts 3–5) | `schema.py` |

The reference "answer key" for the edited files lives in `harness/solution/`.

## What's in here

- `app/` — the Django + Strawberry project, **stock / vulnerable at its
  defaults** (no lab comments, nothing contrived).
- `tasks/` — the five `patch_*` live-endpoint pollers + readiness probe, baked
  to `/opt/graphql-lab-tasks` and called by the challenge's graded tasks.
- `toolbox/` — probe wrappers (`introspect.sh`, `suggest.sh`,
  `dev-defaults-probe.sh`, `alias-probe.sh`, `depth-probe.sh`) plus `reload.sh` /
  `reset.sh`, baked to `/opt/graphql-lab-toolbox` and symlinked to `~/toolbox`.
  The lesson shows learners the raw `curl` / `jq` / `systemctl` commands instead
  of the wrappers; only `reset.sh` is still mentioned (in the terminal welcome).
- `harness/` — a local validation harness proving every technique flips
  vulnerable→patched, in isolation and combined, plus depth-limit boundaries
  and the pollers' separate rate-limit budget (55/55).
- `playground/iximiuz/` — the custom rootfs `Dockerfile` (FROM
  `ghcr.io/iximiuz/labs/rootfs:ubuntu-24-04`), the `graphql-lab.service` systemd
  unit, the custom-playground `manifest.yaml` (a terminal tab plus an
  **Acme Social** browser tab on port 8000), and the build / publish scripts.
- `index.md` — the `kind: challenge` lesson: references the custom playground by
  name, a readiness init task, five graded `verify_*` tasks, and the lesson body
  with `::simple-task` + `::hint-box`.

## Running it locally

Requires Python 3.12+ and the pinned deps:

```bash
cd app
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py seed_data
uvicorn graphql_lab.asgi:application --host 127.0.0.1 --port 8000
```

The API is then at `http://127.0.0.1:8000/graphql/` (GraphiQL in a browser
until step 3 is fixed).

## Validation harness (release gate)

```bash
PYTHON=app/.venv/bin/python UVICORN=app/.venv/bin/uvicorn bash harness/validate.sh
```

For each configuration it boots the app on a fresh port and asserts the five
pollers report the expected state:

- stock defaults → all five **vulnerable**;
- each control alone → **only** that technique secure (orthogonality);
- half of step 3 (only the IDE off, or only errors masked) → still
  **vulnerable**, and `MaskErrors()` without a rule is rejected because it also
  hides validation errors;
- `max_depth` 2 and 6 → **vulnerable**, 3 and 5 → **secure**;
- fully hardened → all five **secure**, and legitimate traffic still works;
- the pollers' POSTs from `127.0.0.2` exhaust only their own rate-limit budget,
  not the learner's on `127.0.0.1`.

The pollers' `--interface 127.0.0.2` needs Linux, where all of `127.0.0.0/8`
is on loopback. Elsewhere, run with `CHECK_SRC=` to send from the default
address; that also skips the rate-limit test.

Exit 0 = gate passed. The harness restores the pristine (vulnerable) `app/`
files on exit, so it is safe to re-run.

## How it's deployed on iximiuz Labs

Three pieces, refreshed together by `playground/iximiuz/publish.sh`:

1. **Rootfs image** — `ghcr.io/lpmi-13/graphql-vuln-lab-rootfs` (public). Bakes
   the project at `/opt/graphql-lab`, a venv at `/opt/graphql-lab-venv`, a
   pristine copy at `/opt/graphql-lab-pristine` (for `reset.sh`), the graders,
   and the toolbox. The database is migrated + seeded at build time. `uvicorn`
   runs under `graphql-lab.service`, which auto-starts at boot. It listens on
   `0.0.0.0:8000` because iximiuz only exposes ports bound to the machine's main
   interface, and the **Acme Social** tab needs it.
2. **Custom playground** — `graphql-vuln-lab-6ac4f832`, a `flexbox`-based
   playground whose `dev-01` machine mounts the rootfs image as its drive.
3. **Challenge** — `graphql-vuln-lab-ca696b14`, which references the playground
   **by name** and adds the graded `verify_*` tasks.

```bash
# Rebuild + push the image, update the playground, push the challenge:
bash playground/iximiuz/publish.sh
```

`publish.sh` reads the current GHCR image tag from the playground manifest,
increments its version (for example, `v9` to `v10`), builds and pushes that
image, then updates the playground and records the new tag in the manifest.

> A `kind: challenge` cannot carry a custom drive inline (`labctl content push`
> rejects it with *"playground must have a name"*). The custom rootfs therefore
> lives in a named custom playground, and the challenge references that name.
> Pushing the image needs a ghcr token with the `write:packages` scope.

## Implementation notes

- Uses the **sync** `strawberry.django.views.GraphQLView` (not the async view)
  so the Django-ORM resolvers stay idiomatic without `sync_to_async`; still
  served by uvicorn over ASGI. All five fixes are schema-/view-level and behave
  identically either way.
- Uses plain `strawberry` types + the Django ORM rather than
  `strawberry-graphql-django`, for the same reason.
- Pollers fail **closed**: a missing/garbled response is treated as "not
  secure", never a pass. Query probes use GET, which the POST rate limit
  ignores.
- Pollers send from `127.0.0.2` (`CHECK_SRC` in `tasks/_common.sh`). The rate
  limiter keys on the client address, so the examiner's retries spend their own
  60/m budget instead of the learner's. The alias poller also sleeps
  `CHECK_DELAY` (2 s) before POSTing, keeping the checker under its own limit.
- The view keeps Strawberry's documented `csrf_exempt` wrapper. With no login
  session there is nothing for CSRF to abuse, and Strawberry already rejects
  the request shapes a cross-site page can send (GET mutations and form or
  plain-text bodies get a `400`).
