# GraphQL Security Lab

An iximiuz Labs challenge: a stock **Django + Strawberry** GraphQL service that
ships with five classic weaknesses. The learner probes each one, hardens the
real project, and a live-polling check flips green. Based on Intigriti's
[Five easy ways to hack GraphQL targets](https://www.intigriti.com/researchers/blog/hacking-tools/five-easy-ways-to-hack-graphql-targets).

## ▶ [Try it live on iximiuz Labs →](https://labs.iximiuz.com/challenges/graphql-vuln-lab-ca696b14)

**https://labs.iximiuz.com/challenges/graphql-vuln-lab-ca696b14**

## The five techniques

| # | Technique | Learner's change | File |
|---|-----------|------------------|------|
| 1 | Introspection enabled | add `DisableIntrospection()` extension | `schema.py` |
| 2 | Field suggestions ("Did you mean") | add `StrawberryConfig(disable_field_suggestions=True)` | `schema.py` |
| 3 | CSRF (view ships `csrf_exempt`) | remove the `csrf_exempt` wrapper | `urls.py` |
| 4 | Alias-packing rate-limit bypass | **write** a custom alias-count validation rule | `validation.py` + `schema.py` |
| 5 | Deep-query DoS | add `QueryDepthLimiter(max_depth=5)` | `schema.py` |

The reference "answer key" for all three edited files lives in `harness/solution/`.

## What's in here

- `app/` — the Django + Strawberry project, **stock / vulnerable at its
  defaults** (no lab comments, nothing contrived).
- `tasks/` — the five `patch_*` live-endpoint pollers + readiness probe, baked
  to `/opt/graphql-lab-tasks` and called by the challenge's graded tasks.
- `toolbox/` — learner probe wrappers (`introspect.sh`, `suggest.sh`,
  `csrf-probe.sh`, `alias-probe.sh`, `depth-probe.sh`) plus `reload.sh` /
  `reset.sh`, baked to `/opt/graphql-lab-toolbox` and symlinked to `~/toolbox`.
- `harness/` — a local validation harness proving every technique flips
  vulnerable→patched, in isolation and combined (35/35).
- `playground/iximiuz/` — the custom rootfs `Dockerfile` (FROM
  `ghcr.io/iximiuz/labs/rootfs:ubuntu-24-04`), the `graphql-lab.service` systemd
  unit, the custom-playground `manifest.yaml`, and the build / publish scripts.
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

The API is then at `http://127.0.0.1:8000/graphql/` (GraphiQL in a browser;
`/api/csrf/` primes a CSRF cookie for mutation clients).

## Validation harness (release gate)

```bash
PYTHON=app/.venv/bin/python UVICORN=app/.venv/bin/uvicorn bash harness/validate.sh
```

For each configuration it boots the app on a fresh port and asserts the five
pollers report the expected state:

- stock defaults → all five **vulnerable**;
- each control alone → **only** that technique secure (orthogonality);
- fully hardened → all five **secure**, and legitimate traffic still works.

Exit 0 = gate passed. The harness restores the pristine (vulnerable) `app/`
files on exit, so it is safe to re-run.

## How it's deployed on iximiuz Labs

Three pieces, refreshed together by `playground/iximiuz/publish.sh`:

1. **Rootfs image** — `ghcr.io/lpmi-13/graphql-vuln-lab-rootfs` (public). Bakes
   the project at `/opt/graphql-lab`, a venv at `/opt/graphql-lab-venv`, a
   pristine copy at `/opt/graphql-lab-pristine` (for `reset.sh`), the graders,
   and the toolbox. The database is migrated + seeded at build time. `uvicorn`
   runs under `graphql-lab.service`, which auto-starts at boot.
2. **Custom playground** — `graphql-vuln-lab-6ac4f832`, a `flexbox`-based
   playground whose `dev-01` machine mounts the rootfs image as its drive.
3. **Challenge** — `graphql-vuln-lab-ca696b14`, which references the playground
   **by name** and adds the graded `verify_*` tasks.

```bash
# Rebuild + push the image, update the playground, push the challenge:
bash playground/iximiuz/publish.sh
```

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
  secure", never a pass. Query probes use GET (CSRF-independent); mutation
  probes send a primed CSRF token.
