# RDBMS for persistence

## Context and Problem Statement

The app needs to store the story maps, historical 
views, audit trail, and workflow data on a per team basis.

## Considered Options

- Relational Database
- Event Sourcing and CQRS

## Decision Outcome

Relational Database

### Consequences

While event sourcing aligns well with the immutable 
event log and timeline navigation features, 
the development and maintenance overhead is too 
expensive. An ACID transaction covering both audit 
and data model persistence provides a straight-forward
implementation without the overhead of writing projections
and reducers.
