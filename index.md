---
title: 'Harden a Django GraphQL API: Five Classic Flaws'

description: |
  A stock Django + Strawberry GraphQL service ships with five common
  weaknesses. Probe each one from the terminal, fix it in the real project, and
  watch the lab confirm the remediation against the live endpoint.

kind: challenge

playground:
  name: graphql-vuln-lab-6ac4f832

difficulty: medium

categories:
  - security

tagz:
  - graphql
  - django
  - strawberry
  - appsec

createdAt: 2026-10-20
updatedAt: 2026-10-20

tasks:
  init_wait_ready:
    name: init_wait_ready
    machine: dev-01
    init: true
    user: root
    timeout_seconds: 300
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/wait_ready.sh

  verify_introspection:
    machine: dev-01
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/patch_introspection.sh

  verify_field_suggestions:
    machine: dev-01
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/patch_field_suggestions.sh

  verify_csrf:
    machine: dev-01
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/patch_csrf.sh

  verify_alias_limit:
    machine: dev-01
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/patch_alias_limit.sh

  verify_depth_limit:
    machine: dev-01
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/patch_depth_limit.sh
---

You've inherited **Acme Social**, a small Django app whose API is served by
[Strawberry](https://strawberry.rocks). It works — and it ships with five
weaknesses that show up again and again in real GraphQL services. The code is a
perfectly ordinary Strawberry/Django setup; the *defaults* are the problem.

Your job: confirm each weakness from the terminal, then fix it in the real
project under `~/graphql-lab`. After each fix, run `~/toolbox/reload.sh` and the
lab will re-check the live endpoint.

The project you edit:

- `~/graphql-lab/graphql_lab/schema.py` — where the schema is built.
- `~/graphql-lab/graphql_lab/urls.py` — where the view is wired up.

Nothing in the code is commented to tell you what to change — that's the point.
Everything you need is below.

## 1. Introspection is wide open

GraphQL introspection lets a client download the entire schema. Handy in
development, a gift to an attacker in production.

```bash
~/toolbox/introspect.sh      # dumps every type and field if introspection is on
```

Disable introspection in the schema, then `~/toolbox/reload.sh`.

::simple-task
---
:tasks: tasks
:name: verify_introspection
---
#active
Checking whether introspection still returns the schema...

#completed
Introspection is disabled — the schema no longer leaks.
::

::hint-box
---
:summary: Hint
---
Strawberry ships a schema **extension** for exactly this. Extensions are passed
to `strawberry.Schema(..., extensions=[...])`. Look at
[`DisableIntrospection`](https://strawberry.rocks/docs/extensions/disable-introspection).
::

## 2. Error messages suggest real field names

Turning off introspection isn't enough. Ask for a field that *almost* exists and
the server helpfully corrects you — rebuilding the schema one guess at a time.

```bash
~/toolbox/suggest.sh         # misspells a field; watch for "Did you mean ...?"
```

Make the server stop suggesting field names, then reload.

::simple-task
---
:tasks: tasks
:name: verify_field_suggestions
---
#active
Checking whether errors still suggest real field names...

#completed
Field suggestions are disabled — errors no longer name real fields.
::

::hint-box
---
:summary: Hint
---
This one is a **schema config** flag, not an extension:
`strawberry.Schema(..., config=StrawberryConfig(disable_field_suggestions=True))`.
Import `StrawberryConfig` from `strawberry.schema.config`.
::

## 3. State-changing requests have no CSRF protection

The GraphQL view is wrapped in `csrf_exempt` (straight from Strawberry's own
Django docs). That means any site can POST a mutation to it in a logged-in
user's browser.

```bash
~/toolbox/csrf-probe.sh      # a forged, tokenless mutation POST — currently 200
```

Make Django enforce CSRF on the endpoint again, then reload. (A request that
carries a valid CSRF token must still work — the checker verifies both.)

::simple-task
---
:tasks: tasks
:name: verify_csrf
---
#active
Checking whether forged, tokenless mutations are rejected...

#completed
CSRF is enforced — forged POSTs are rejected while valid ones still work.
::

::hint-box
---
:summary: Hint
---
The fix is a deletion, not an addition. Look at how the view is wrapped in
`graphql_lab/urls.py` and let Django's `CsrfViewMiddleware` do its job. A
browser client primes its token from `GET /api/csrf/`.
::

## 4. Field aliases bypass the rate limiter

The endpoint has a per-request rate limiter, so a brute-force of the
`verifyOtp` mutation should be slow. But GraphQL lets one request alias the same
field many times — and the limiter counts that as a *single* request.

```bash
~/toolbox/alias-probe.sh     # 60 OTP attempts in ONE request
```

There's no built-in alias cap in Strawberry/Python, so you'll **write** one: a
small graphql-core validation rule that counts aliased fields and rejects a
request with too many. Put it in a new file `graphql_lab/validation.py` and
register it on the schema, then reload.

::simple-task
---
:tasks: tasks
:name: verify_alias_limit
---
#active
Checking whether an alias-packed request is rejected...

#completed
Alias abuse is capped — packed requests are rejected, normal ones still work.
::

::hint-box
---
:summary: Hint 1
---
Subclass `graphql.validation.ValidationRule`. Implement `enter_field(self,
node, *_)`, count the ones where `node.alias` is set, and call
`self.report_error(GraphQLError(...))` past your threshold.
::

::hint-box
---
:summary: Hint 2
---
Register the rule with the `AddValidationRules([...])` extension (from
`strawberry.extensions`). Strawberry also ships `MaxAliasesLimiter` if you'd
rather use the built-in — but writing the rule is the point here.
::

## 5. A single deep query can exhaust the server

`Post.author` and `User.posts` reference each other, so a query can nest as
deep as a client likes. With no depth limit, one request can force an enormous
amount of work.

```bash
~/toolbox/depth-probe.sh     # a deeply nested query that currently resolves
```

Add a query-depth limit to the schema, then reload. (A normal shallow query
must still work.)

::simple-task
---
:tasks: tasks
:name: verify_depth_limit
---
#active
Checking whether deeply nested queries are rejected...

#completed
Query depth is capped — deep queries are rejected, shallow ones still work.
::

::hint-box
---
:summary: Hint
---
Another extension:
[`QueryDepthLimiter(max_depth=...)`](https://strawberry.rocks/docs/extensions/query-depth-limiter)
from `strawberry.extensions`. Pick a limit that rejects the probe's nesting but
allows ordinary queries.
::

## Done

You've taken a stock GraphQL service and closed the five weaknesses from
Intigriti's [Five easy ways to hack GraphQL
targets](https://www.intigriti.com/researchers/blog/hacking-tools/five-easy-ways-to-hack-graphql-targets):
introspection, field suggestions, CSRF, alias-based rate-limit bypass, and
unbounded query depth. Same service, hardened defaults.
