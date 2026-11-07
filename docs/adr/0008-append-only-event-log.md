# Append-only event log

## Context and Problem Statement

The four views (map, flow, teamwork, inventory) all derive
from the same underlying data. Every mutation must be
traceable for audit, metrics, and history display.

## Considered Options

- Event sourcing with projections
- Mutable state with a separate audit table
- Mutable state with inline event recording

## Decision Outcome

Mutable state with inline event recording. Every mutation
writes both the state change and an immutable event row
inside a single ACID transaction.

### Consequences

The events table is append-only and never modified. Flow
charts, pairing matrices, and history views all read from
it. This gives the auditability of event sourcing without
the projection and replay machinery. The tradeoff is that
events are a secondary record, not the source of truth,
so the schema must be disciplined about always recording
them.
