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

Your job: confirm each weakness from the terminal with `curl` and `jq`, then fix
it in the real project under `~/graphql-lab`. After each fix, restart the
service so your changes take effect, and the lab will re-check the live
endpoint:

```bash
sudo systemctl restart graphql-lab.service
```

It takes a couple of seconds to come back up. If it doesn't (a typo in your
edit, say), `sudo systemctl status graphql-lab.service` shows why.

The project you edit:

- `~/graphql-lab/graphql_lab/schema.py` — where the schema is built.
- `~/graphql-lab/graphql_lab/urls.py` — where the view is wired up.

Nothing in the code is commented to tell you what to change — that's the point.
Everything you need is below.

## 1. Introspection is wide open

GraphQL introspection lets a client download the entire schema. Handy in
development, a gift to an attacker in production.

```bash
curl -fsS -G http://127.0.0.1:8000/graphql/ \
  --data-urlencode 'query={__schema{queryType{name} types{name kind fields{name}}}}' \
  | jq .
```

`-G` turns `--data-urlencode` into a URL query string, so this is a plain
`GET /graphql/?query=...`. If introspection is on, the response lists every
type and every field.

Disable introspection in the schema, then restart the service.

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
curl -fsS -G http://127.0.0.1:8000/graphql/ \
  --data-urlencode 'query={ usrs { id } }' \
  | jq -r '.errors[].message'
```

There's no `usrs` field, so the query fails. Watch the error message for
`Did you mean ...?`

Make the server stop suggesting field names, then restart the service.

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
curl -s -o /dev/null -w 'HTTP %{http_code}\n' \
  -X POST http://127.0.0.1:8000/graphql/ \
  -H 'content-type: application/json' \
  -d '{"query":"mutation{ updateBio(text:\"owned\"){ ok } }"}'
```

This is what a forged cross-site request looks like: a state-changing mutation
with no CSRF cookie and no token. `HTTP 200` means it was accepted (vulnerable);
`HTTP 403` means Django rejected it (fixed).

Make Django enforce CSRF on the endpoint again, then restart the service. (A
request that carries a valid CSRF token must still work — the checker verifies
both.)

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

First build one mutation that packs 60 OTP guesses, each under its own alias
(`a0`, `a1`, ...):

```bash
Q="mutation{ $(for i in $(seq 0 59); do printf 'a%d: verifyOtp(code:"%04d"){ ok } ' "$i" "$i"; done)}"
echo "$Q"
```

Then send it as a single POST. Once you've fixed CSRF in step 3 the endpoint
wants a token, so fetch one from `/api/csrf/` and send it back as both the
cookie and the `X-CSRFToken` header, the same way a legitimate client does:

```bash
TOKEN="$(curl -s -o /dev/null -c - http://127.0.0.1:8000/api/csrf/ | awk '$6 == "csrftoken" {print $7}')"

curl -s -X POST http://127.0.0.1:8000/graphql/ \
  -H 'content-type: application/json' \
  -b "csrftoken=$TOKEN" -H "X-CSRFToken: $TOKEN" \
  --data "$(jq -nc --arg q "$Q" '{query: $q}')" \
  | jq '{attempts: (.data | length), errors: (.errors | length)}'
```

`jq -n --arg` wraps the query in a JSON request body and handles the quoting.
`attempts: 60` means all 60 guesses ran inside one rate-limited request.

There's no built-in alias cap in Strawberry/Python, so you'll **write** one: a
small graphql-core validation rule that counts aliased fields and rejects a
request with too many. Put it in a new file `graphql_lab/validation.py` and
register it on the schema, then restart the service.

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
curl -s -G http://127.0.0.1:8000/graphql/ \
  --data-urlencode 'query={ me{ posts{ author{ posts{ author{ posts{ author{ posts{ id }}}}}}}} }' \
  | jq '{data_present: (.data != null), errors: (.errors | length)}'
```

`data_present: true` with no errors means the server resolved the whole chain
(vulnerable). A depth-limit error means it refused (fixed).

Add a query-depth limit to the schema, then restart the service. (A normal
shallow query must still work.)

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
