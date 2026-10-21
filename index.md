---
title: 'Harden a Django GraphQL API: Five Classic Flaws'

description: |
  A stock Django + Strawberry GraphQL service ships with five common
  weaknesses. Probe each one from the terminal, fix it in the real project, and
  watch the lab confirm the remediation against the live endpoint.

kind: challenge

playground:
  name: graphql-vuln-lab-6ac4f832

difficulty: easy

categories:
  - security

tagz:
  - graphql
  - django
  - strawberry
  - appsec

createdAt: 2026-10-20
updatedAt: 2026-10-21

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

  verify_dev_defaults:
    machine: dev-01
    run: |-
      #!/bin/bash
      /opt/graphql-lab-tasks/patch_dev_defaults.sh

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

Here's the path a request takes through this lab:

```text
curl / browser
    │  HTTP GET or POST /graphql/ with a GraphQL query or mutation
    ▼
Uvicorn server (port 8000)
    ▼
Django: route request, apply the POST rate limit
    ▼
Strawberry GraphQL view: parse and validate against the schema
    ▼
Execute fields → resolvers → Django ORM → SQLite database
    │
    └── JSON response (data or errors) ──→ curl / browser
```

GraphQL validation can reject a query before any resolver runs.

**Based on:** Intigriti's [Five easy ways to hack GraphQL
targets](https://www.intigriti.com/researchers/blog/hacking-tools/five-easy-ways-to-hack-graphql-targets),
though the lab doesn't follow the article step for step. It keeps the
introspection, field-suggestion and alias techniques. It shows denial of service
with deeply nested queries instead of batched ones. And it swaps the article's
CSRF section for two production-readiness checks, because this demo API has no
login for a CSRF attack to abuse. For the wider security principles behind the
exercises, see [GraphQL's security guide](https://graphql.org/learn/security/).

Your job: confirm each weakness from the terminal with `curl` and `jq` (step 3
also uses the **Acme Social** browser tab), then fix it in the real project
under `~/graphql-lab`. After each fix, restart the
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

[GraphQL introspection](https://graphql.org/learn/introspection/) lets a client
download the entire schema. Handy in development, a gift to an attacker in
production.

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
[Strawberry's `DisableIntrospection` documentation](https://strawberry.rocks/docs/extensions/disable-introspection).
::

## 2. Error messages suggest real field names

Turning off introspection isn't enough. Ask for a field that *almost* exists and
the server helpfully corrects you — rebuilding the schema one guess at a time.
[GraphQL's security guide explains the risk of revealing field names through
error messages](https://graphql.org/learn/security/#error-messages); the
[Clairvoyance tool](https://github.com/nikitastupin/clairvoyance) linked in the
Intigriti article automates that kind of schema discovery.

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
This one is a **schema config** flag, not an extension. See
[Strawberry's `disable_field_suggestions` documentation](https://strawberry.rocks/docs/types/schema-configurations#disable_field_suggestions).
::

## 3. Development defaults are still switched on

Two Strawberry defaults help while you build an API, but give away too much
once it's live:

- **The GraphiQL IDE.** Open `/graphql/` in a browser and Strawberry serves an
  interactive query editor with autocomplete and a schema explorer. Anyone who
  finds the endpoint gets a ready-made tool for probing it.
- **Raw resolver errors.** When code inside a resolver raises an exception,
  Strawberry sends the exception's message back to the client unchanged.

Open the **Acme Social** tab, which shows the app's front page, and follow the
`/graphql/` link. You land in GraphiQL. The browser gets the IDE because it
asks for HTML, so send the same kind of request from the terminal:

```bash
curl -s -o /dev/null -w 'HTTP %{http_code}\n' \
  -H 'accept: text/html' http://127.0.0.1:8000/graphql/
```

`HTTP 200` means the IDE page is served.

Now look up a post by ID, once with a malformed ID and once with an ID that
doesn't exist:

```bash
for id in abc 999; do
  curl -fsS -G http://127.0.0.1:8000/graphql/ \
    --data-urlencode "query={ post(id: \"$id\") { title } }" \
    | jq -r '.errors[].message'
done
```

```text
Field 'id' expected a number but got 'abc'.
Post matching query does not exist.
```

Both messages are Django's own wording, raised by the resolver's
`Post.objects.get(...)` call. They tell an attacker the API runs on Django's
ORM, and they name a model (`Post`) and a model field (`id`) with its type. A
client only needs to know that the lookup failed.

Make two changes, then restart the service:

1. Switch off the IDE where the view is wired up, in `graphql_lab/urls.py`.
2. Mask resolver errors in `graphql_lab/schema.py`. Mask **only** errors raised
   inside resolvers. GraphQL's own validation errors, such as a misspelled
   field or the limits you'll add in steps 4 and 5, describe the client's query
   rather than your code, so they should stay readable.

Masking hides the details from clients, not from you: the full exception still
goes to the service log, and `sudo systemctl status graphql-lab.service` shows
its last lines.

Once both changes are live, the IDE request returns `HTTP 404` (the tab's
`/graphql/` link shows `Not Found`) and both lookups print `Unexpected error.`
The check also confirms that a misspelled field still gets its validation
message and that a lookup with a real ID still works.

::simple-task
---
:tasks: tasks
:name: verify_dev_defaults
---
#active
Checking whether the IDE is still served and resolver errors still leak...

#completed
The IDE is off and resolver errors are masked.
::

::hint-box
---
:summary: Hint 1
---
The IDE is an option of the view, not the schema: `GraphQLView.as_view(...)`
accepts `graphql_ide=None`. See the options in
[Strawberry's Django integration documentation](https://strawberry.rocks/docs/integrations/django).
::

::hint-box
---
:summary: Hint 2
---
Another extension: `MaskErrors` from `strawberry.extensions`. On its own it
masks every error, validation errors included, so give it a rule. Only
exceptions raised inside resolvers carry an `original_error`:
`MaskErrors(should_mask_error=lambda error: error.original_error is not None)`.
See [Strawberry's `MaskErrors` documentation](https://strawberry.rocks/docs/extensions/mask-errors).
::

## 4. Field aliases bypass the rate limiter

The endpoint has a per-request rate limiter (60 POSTs a minute per client
address), so a brute-force of the `verifyOtp` mutation should be slow. But
GraphQL lets one request
[alias the same field many times](https://graphql.org/learn/queries/#aliases) —
and the limiter counts that as a *single* request.

First build one mutation that packs 60 OTP guesses, each under its own alias
(`a0`, `a1`, ...):

```bash
Q="mutation{ $(for i in $(seq 0 59); do printf 'a%d: verifyOtp(code:"%04d"){ ok } ' "$i" "$i"; done)}"
echo "$Q"
```

Then send it as a single POST:

```bash
curl -s -X POST http://127.0.0.1:8000/graphql/ \
  -H 'content-type: application/json' \
  --data "$(jq -nc --arg q "$Q" '{query: $q}')" \
  | jq '{attempts: (.data | length), errors: (.errors | length)}'
```

`jq -n --arg` wraps the query in a JSON request body and handles the quoting.
`attempts: 60` means all 60 guesses ran inside one rate-limited request.
[GraphQL's security guide recommends limiting aliases within an
operation](https://graphql.org/learn/security/#breadth-and-batch-limiting).

Strawberry provides a built-in alias limiter, but in this exercise you'll
**write** a small graphql-core validation rule that counts aliased fields and
rejects a request with too many. Define the rule in `graphql_lab/schema.py`,
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
Return `BREAK` (from `graphql.language`) after reporting so your rule emits
only one error for an oversized request.
::

::hint-box
---
:summary: Hint 2
---
Register the rule with the
[`AddValidationRules([...])` extension](https://strawberry.rocks/docs/extensions/add-validation-rules)
(from `strawberry.extensions`). Strawberry also ships
[`MaxAliasesLimiter`](https://strawberry.rocks/docs/extensions/max-aliases-limiter)
if you'd rather use the built-in — but writing the rule is the point here.
::

## 5. A single deep query can exhaust the server

`Post.author` and `User.posts` reference each other, so a query can nest as
deep as a client likes. With no depth limit, one request can force an enormous
amount of work. [GraphQL's security guide recommends limiting operation
depth](https://graphql.org/learn/security/#depth-limiting).

```bash
curl -s -G http://127.0.0.1:8000/graphql/ \
  --data-urlencode 'query={ me{ posts{ author{ posts{ author{ posts{ id }}}}}} }' \
  | jq '{data_present: (.data != null), errors: (.errors | length)}'
```

`data_present: true` with no errors means the server resolved the whole chain
(vulnerable). A depth-limit error means it refused (fixed).

### Work out the limit

A depth limit applies to every query, including the ones the app's own pages
send. Set it too low and real pages break; set it too high and the probe gets
through. The right value is **the highest depth this application is likely to
need**. Work it out in three steps.

**1. Learn how depth is counted.** Strawberry's `QueryDepthLimiter` follows the
longest path from the query root and counts its fields, **except** the leaf
field at the end. Braces do not add depth. The probe above is
`me (1) → posts (2) → author (3) → posts (4) → author (5) → posts (6) → id`,
so it has depth 6.

**2. Count the depth of the queries the app needs.** Acme Social's pages send
queries like these:

- **Profile page** — your name and your post titles:
  `{ me { username posts { title } } }` is
  `me (1) → posts (2) → title`, depth 2.
- **Post page** — the post, its author, and the author's other posts:
  `{ post(id: "1") { title author { username posts { title } } } }` is
  `post (1) → author (2) → posts (3) → title`, depth 3.

**3. Find the highest depth the app is likely to need.** Try going one level
past the post page: `post → author → posts → author`. That last `author` is the
author of the author's own posts, the same user the query already fetched at
level 2. Every level past 3 just goes round the `posts → author` loop again and
returns users and posts the query already has. So no sensible page needs more
than depth 3: that is the highest depth this application is likely to need.

That number is your limit: **`max_depth=3`**. It allows both pages and rejects
the depth-6 probe. A lower cap breaks real pages: `max_depth=1` rejects the
profile page and `max_depth=2` the post page, which is why you can't simply set
the smallest possible limit. If Acme Social later adds a page that needs deeper
data, redo the count and raise the limit to match.

Add the limit to the schema, then restart the service. Then check both sides:
the probe above should now get a depth-limit error, and the post page should
still return data:

```bash
curl -s -G http://127.0.0.1:8000/graphql/ \
  --data-urlencode 'query={ post(id: "1") { title author { username posts { title } } } }' \
  | jq .
```

The check sends both queries.

::simple-task
---
:tasks: tasks
:name: verify_depth_limit
---
#active
Checking whether deeply nested queries are rejected...

#completed
Query depth is capped — deep queries are rejected, normal ones still work.
::

::hint-box
---
:summary: Hint
---
Another extension: `QueryDepthLimiter(max_depth=...)` from
`strawberry.extensions`. See [Strawberry's `QueryDepthLimiter` documentation](https://strawberry.rocks/docs/extensions/query-depth-limiter).
Pass it the depth you worked out above.
::

## Done

You've taken a stock GraphQL service and closed five weaknesses: introspection,
field suggestions, development defaults left on (the GraphiQL IDE and raw
resolver errors), alias-based rate-limit bypass, and unbounded query depth.
Same service, hardened defaults.
