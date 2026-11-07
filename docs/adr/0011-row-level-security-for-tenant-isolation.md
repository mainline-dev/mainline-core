# Row Level Security for tenant isolation

## Context and Problem Statement

The app is multi-tenant. Every team-scoped table has a
`team_id` column. Queries must never return rows belonging
to a different team, even if application code has a bug.

## Considered Options

- Application-level scoping (WHERE clauses, Sequel plugins)
- PostgreSQL Row Level Security (RLS)
- Separate schemas per tenant

## Decision Outcome

PostgreSQL RLS. Every table with a `team_id` column gets a
`team_isolation` policy gated on a connection-local GUC
(`app.current_team_id`). The database enforces isolation
regardless of what the application does.

A dedicated `mainline_app` DB role runs with RLS enforced.
The migration role (`mainline`) owns the tables and bypasses
RLS for migrations and `delete_team_data()`.

A second GUC (`app.rls_bypass`) allows cross-team reads
within the app (team list, webhook handlers) without
switching to the superuser role. `BypassRLS.call { }` wraps
these in a savepoint and resets the flag on exit.

`SetTeamContext.call(team_id)` sets the GUC. Both GUCs are
transaction-scoped (`true` flag) so PostgreSQL clears them
automatically at COMMIT/ROLLBACK (see ADR 0010).

### Consequences

Every new table with `team_id` must enable RLS and add a
`team_isolation` policy. `lib/delete_team.rb` must clean up
the table. Missing either is a data leak or an orphan.

### Accepted exception: team_memberships

`team_memberships` has a `team_id` but deliberately no RLS.
Authentication has to read a person's memberships to discover
which teams they belong to before any team context can exist
(`app.rb` team picker, membership checks on every team route).
The table carries only the person-team edge and flags - no
team content. All reads are scoped by `person_id` or checked
against the session person in application code.

### Tables without team_id

Tables that hang off a team-scoped parent (`scenarios` via
`stories`; `tracked_branches` and `integration_events` via
`monitored_repos`) use a transitive policy: an EXISTS check
against the parent, which is itself under RLS. Their isolation
is only as strong as the parent's policy - widening a parent's
policy silently widens the children.
