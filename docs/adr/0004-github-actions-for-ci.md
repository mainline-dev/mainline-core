# Github actions for CI

## Context and Problem Statement

The app must be tested and deployed automatically on every 
commit. The CI tool should support decoupling deployments
from releases, and be cheap enough or have a free tier.

## Considered Options

- Github actions
- CircleCI
- etc, etc.

## Decision Outcome

Github actions

### Consequences

Github actions may not have improved its capability to
actually support CI and CD over the years. 
Trying it out for now, switching if not.
