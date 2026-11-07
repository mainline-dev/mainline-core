# Fork-safe DB connections and transaction-scoped RLS

## Context and Problem Statement

Under concurrent load on production (Puma 8, 2 workers, 5 threads),
authenticated routes returned data from wrong tables. `Person[uuid]`
returned rows whose `id` was a team UUID. Debug logging confirmed
session values were correct but query results crossed between
processes.

Two independent bugs were found:

1. Puma preloads the app before forking workers. During preload,
   `require_valid_schema` validates every model against the
   database, opening connections. After fork, both workers
   inherit the same file descriptors to the same PostgreSQL
   sockets. Two OS processes writing to the same socket causes
   result-buffer crossover -- one process reads another's query
   response.

2. ADR 0009 used `DB.synchronize` with `set_config(name, value,
   false)`. The `false` makes the GUC session-scoped -- it
   persists on the connection after the request ends. When
   another thread checks out that connection, it inherits the
   stale `app.current_team_id`, and RLS filters against the
   wrong team. Single-threaded Puma masked this because one
   thread overwrites the GUC each request.

## Considered Options

- `on_worker_boot { DB.disconnect }` alone (fixes fork, not GUC leak)
- `DB.synchronize` with manual GUC reset at request start (fragile)
- `DB.transaction` with `set_config(name, value, true)` (transaction-local)
- Rack middleware wrapping `@app.call(env)` in a transaction

## Decision Outcome

Two changes, addressing orthogonal failure modes:

### Fork safety (config/puma.rb)

`preload_app!` is explicit. `before_fork` disconnects in the
parent so children do not inherit live file descriptors.
`on_worker_boot` disconnects again as belt-and-suspenders.
Sequel reconnects lazily on first query.

### Transaction-scoped RLS (app.rb, set_team_context.rb, bypass_rls.rb)

`DB.synchronize` replaced with `DB.transaction`. All
`set_config` calls changed from `false` (session-local) to
`true` (transaction-local). PostgreSQL reverts transaction-local
GUCs at COMMIT or ROLLBACK automatically. No application-side
cleanup required.

This supersedes ADR 0009. The connection-pinning guarantee is
preserved because `DB.transaction` calls `pool.hold` internally.

Roda's `throw :halt` (used by `r.redirect`, `r.halt`, route
matchers) is handled correctly: Sequel's transaction ensure
block commits on non-exception exits. All four exit paths
(normal return, throw, exception, Sequel::Rollback) clear GUCs
because PostgreSQL clears them at transaction end regardless
of COMMIT or ROLLBACK.

Write routes already wrap mutations in nested `DB.transaction`
blocks (which become savepoints under the outer transaction)
and validate before writing, so there is no risk of a halted
request accidentally committing partial writes.

### Consequences

Pool size must still match thread count (ADR 0009 still applies).
Each authenticated request now holds a transaction open for
its duration. This is milliseconds and functionally identical
to the previous `DB.synchronize` hold time.

Adding workers later requires checking PostgreSQL
`max_connections` (workers x threads x instances + overhead).
Current budget: 2 x 5 = 10 of 100.

### How this was caught

The fork-safety bug did not surface in tests or local
development. It was only caught by K6 load testing against
the dev server (2 workers, 5 threads, 13 concurrent VUs).
Single-threaded or single-worker configurations masked both
bugs entirely.

Any change to Puma workers/threads, connection pooling,
database hosting, or the preload/fork lifecycle should be
validated with `k6 run scripts/loadtest.js` against a
multi-worker deployment before reaching production.
