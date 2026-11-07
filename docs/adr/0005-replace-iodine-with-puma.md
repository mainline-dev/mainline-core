# Replace Iodine with Puma

## Context and Problem Statement

GHSA-2x79-gwq3-vxxm disclosed an infinite loop DoS in
iodine's vendored JSON parser (facil.io). Any HTTP request
with `Content-Type: application/json` and malformed input
like `[i` can hang a worker indefinitely. No patched gem
version exists. The project is minimally maintained with
months between commits.

Iodine was originally chosen (ADR 0001) for its native SSE
support, anticipating real-time map updates. That feature
was never used. All interactivity is standard HTMX
request/response.

## Considered Options

- Wait for iodine to ship a fix
- Pin iodine to the git commit containing the fix
- Replace with Puma

## Decision Outcome

Replace with Puma 8.0.

Puma is the most widely deployed Ruby application server,
actively maintained, and a drop-in Rack replacement. No
application code changes were required.

Production runs `puma -p 3000 -w 2 -t 5:5` (2 workers,
5 threads each). Dev continues to use `rackup`.

### Consequences

The iodine security vulnerability is eliminated.
If real-time push is needed later, SSE can be done via
Rack hijack or a separate process. That is a future
decision, not a current requirement.
