# Pin DB connection per request

## Context and Problem Statement

PostgreSQL Row Level Security (RLS) filters rows based on a
connection variable (`app.current_team_id`) set via `set_config`.
Sequel's connection pool checks out a connection per query and
returns it immediately. In a multi-threaded Puma process,
`set_config` can run on connection A while the next query runs
on connection B, which has no team context. RLS then returns
zero rows or blocks writes.

This was not caught by tests because the test pool is
single-threaded and almost always returns the same connection.

## Considered Options

- Wrap each request in `DB.synchronize` (pin one connection)
- Store team ID in `Thread.current` and set it on every pool checkout
- Set the connection variable inside every `DB.transaction` block

## Decision Outcome

`DB.synchronize` wraps only the authenticated route block
inside `app.rb`. Static assets, health checks, and public
pages (login, pricing, docs) do not hold a DB connection.
Authenticated routes pin one connection for the duration of
the request so `set_config` persists across all queries.

DB pool size (db.rb) should be at least equal to the Puma
thread count (Dockerfile) since every authenticated request
holds a connection. Both default to 5.

### Consequences

Public pages and assets are connection-free, so a burst of
static requests cannot exhaust the pool. Authenticated routes
hold connections slightly longer (during template rendering)
but this is milliseconds. No contention as long as pool size
matches thread count.
