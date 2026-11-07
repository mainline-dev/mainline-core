# HTMX and Sortable.js for UI

## Context and Problem Statement

The entry point of the UI is a user story map, visually, the 
user stories are shown as "cards" on rows. They need to 
be moved around via drag and drop.

The UI should feel dynamic, or at least support being 
progressively enhanced iteratively. 

The app should not be an SPA, but reflect the islands design
pattern instead, this is to avoid an SPA framework from 
taking over.

Events need to be sent to the server without
reloading the entire page.

## Considered Options

- Sortable
- Draggable
- Datastar
- HTMX

## Decision Outcome

HTMX + Sortable + _hyperscript

The source of truth is the audit log on the server
side, therefore a full responsive or reactive 
front-end is not required at this time. 
Sortable has enough built in to be useable out of 
the box.

### Consequences

By keeping the logic on the server, whatever the user
does on the font-end cannot break the rules of the app. 
This trades off a little bit of UI polish for 
architectural integrity.
