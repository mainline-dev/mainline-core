# Iodine and Roda for server side

## Context and Problem Statement

This is a multi-tenant UI driven web app MVP. The technology 
should support rapid development, minimal boilerplate, 
have mature testing frameworks, and a small server footprint.
There is no need to "scale" at this point in time, or spend 
any effort in future-proofing hypotheticals. The primary 
goal that this point is to actually build the thing.

## Considered Options

- Sinatra
- Roda
- Ktor
- Quarkus

## Decision Outcome

Roda + Iodine

Roda will be the web framework and Iodine the 
Rack-compatible HTTP/WebSocket server.

### Consequences

DX.
Roda performs well compared to other Ruby frameworks.
Small footprint to match low cost server.
Less boilerplate code to write in Ruby at the expense of 
type safety in Kotlin or Java.
Iodine provides native SSE support, for when real-time map 
updates are needed.
