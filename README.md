# GraphQL Security Lab

An iximiuz Labs challenge: a stock **Django + Strawberry** GraphQL service that
ships with five classic weaknesses. The learner probes each one, hardens the
real project, and a live-polling check flips green. Based on Intigriti's
[Five easy ways to hack GraphQL targets](https://www.intigriti.com/researchers/blog/hacking-tools/five-easy-ways-to-hack-graphql-targets).

Full design: `../../plan-docs/GRAPHQL_SECURITY_LAB_PLAN.md`.

## Status

Implemented and verified locally (plan §13 steps 1–4):

- `app/` — the Django + Strawberry project, **stock/vulnerable at its defaults**
  (no lab comments, nothing contrived).
- `tasks/` — the five `patch_*` live-endpoint pollers + readiness probe (baked
  to `/opt/graphql-lab-tasks` and called by the challenge's graded tasks).
- `toolbox/` — learner probe wrappers + `reload.sh` / `reset.sh` (baked to
  `/opt/graphql-lab-toolbox`, symlinked to `~/toolbox`).
- `harness/` — a local validation harness proving every technique flips
  vulnerable→patched, in isolation and combined (35/35).
- `playground/iximiuz/` — the custom rootfs `Dockerfile` (FROM
  `ghcr.io/iximiuz/labs/rootfs:ubuntu-24-04`), systemd units, bootstrap, build +
  publish scripts, and a standalone `manifest.yaml`.
- `index.md` — the `kind: challenge` lesson: custom-drive `playground`, a
  readiness init task, five graded `verify_*` tasks, and the lesson body with
  `::simple-task` + `::hint-box`.

Verified in the **built rootfs image**: stock defaults report all five
vulnerable; applying the `harness/solution/` files and restarting flips all five
to secure.

**Not yet done (outward-facing, needs a go-ahead):** push the rootfs image to
`ghcr.io/lpmi-13/graphql-vuln-lab-rootfs:v2` and publish the challenge with
`labctl`. That first publish is also where the plan's §2 assumption gets
confirmed — see below.

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

## Building the rootfs image

```bash
bash playground/iximiuz/build-rootfs-image.sh          # build only
ROOTFS_IMAGE=ghcr.io/lpmi-13/graphql-vuln-lab-rootfs:v2 PUSH_IMAGE=1 \
  bash playground/iximiuz/build-rootfs-image.sh         # build + push
```

The image bakes the project at `/opt/graphql-lab`, a venv at
`/opt/graphql-lab-venv`, a pristine copy at `/opt/graphql-lab-pristine`, the
graders at `/opt/graphql-lab-tasks`, and the toolbox at
`/opt/graphql-lab-toolbox`; uvicorn runs under `graphql-lab.service`.

## Publishing

```bash
bash playground/iximiuz/publish.sh     # build+push image, then labctl content push
```

**Plan §2 — resolved at publish.** A `kind: challenge` **cannot** carry a custom
drive inline (`labctl content push` rejects it: *"playground must have a
name"*). The working model is a two-part publish:

1. Register the custom rootfs as a **named custom playground**:
   `labctl playground create graphql-vuln-lab --base flexbox -f playground/iximiuz/manifest.yaml`
   → it gets a suffixed name, e.g. `graphql-vuln-lab-6ac4f832`.
2. The challenge's front matter references it by name: `playground: { name: graphql-vuln-lab-6ac4f832 }`.

Both are live (author-private):
`https://labs.iximiuz.com/playgrounds/graphql-vuln-lab-6ac4f832` and
`https://labs.iximiuz.com/challenges/graphql-vuln-lab-ca696b14`. The playground
pulls the rootfs image by its `oci://…` URL, so the image must be pushed to ghcr
(a PAT with `write:packages`) before the playground can start.

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
