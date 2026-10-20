# GraphQL Security Lab

An iximiuz Labs challenge: a stock **Django + Strawberry** GraphQL service that
ships with five classic weaknesses. The learner probes each one, hardens the
real project, and a live-polling check flips green. Based on Intigriti's
[Five easy ways to hack GraphQL targets](https://www.intigriti.com/researchers/blog/hacking-tools/five-easy-ways-to-hack-graphql-targets).

Full design: `../../plan-docs/GRAPHQL_SECURITY_LAB_PLAN.md`.

## Status

Implemented and verified so far (plan §13 steps 1 & 3):

- `app/` — the Django + Strawberry project, **stock/vulnerable at its defaults**
  (no lab comments, nothing contrived).
- `tasks/` — the five `patch_*` live-endpoint pollers + readiness probe.
- `harness/` — a local validation harness that proves every technique flips
  vulnerable→patched with the intended change, in isolation and combined.

Still to do: rootfs Dockerfile + systemd unit + toolbox (§9/§10), and `index.md`
(§8). See the plan.

## The five techniques

| # | Technique | Learner's change | File |
|---|-----------|------------------|------|
| 1 | Introspection enabled | add `DisableIntrospection()` extension | `schema.py` |
| 2 | Field suggestions ("Did you mean") | add `StrawberryConfig(disable_field_suggestions=True)` | `schema.py` |
| 3 | CSRF (view ships `csrf_exempt`) | remove the `csrf_exempt` wrapper | `urls.py` |
| 4 | Alias-packing rate-limit bypass | **write** a custom alias-count validation rule | `validation.py` + `schema.py` |
| 5 | Deep-query DoS | add `QueryDepthLimiter(max_depth=5)` | `schema.py` |

The reference "answer key" for all three edited files lives in `harness/solution/`.

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
cd <repo root>
PYTHON=app/.venv/bin/python UVICORN=app/.venv/bin/uvicorn bash harness/validate.sh
```

For each configuration it boots the app on a fresh port and asserts the five
pollers report the expected state:

- stock defaults → all five **vulnerable**;
- each control alone → **only** that technique secure (orthogonality);
- fully hardened → all five **secure**, and legitimate traffic still works.

Exit 0 = gate passed. The harness restores the pristine (vulnerable) `app/`
files on exit, so it is safe to re-run.

## Notes / deviations from the plan

- Uses the **sync** `strawberry.django.views.GraphQLView` (not the async view)
  so the Django-ORM resolvers stay idiomatic without `sync_to_async`; still
  served by uvicorn over ASGI. All five fixes are schema-/view-level and behave
  identically either way.
- Uses plain `strawberry` types + the Django ORM rather than
  `strawberry-graphql-django`, for the same reason.
- Pollers fail **closed**: a missing/garbled response is treated as "not
  secure", never a pass. Query probes use GET (CSRF-independent); mutation
  probes send a primed CSRF token.
