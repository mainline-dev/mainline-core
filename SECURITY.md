# Security

Please report vulnerabilities by email to security@mainline.dev, not in a public issue or pull request.

Include what you found, the steps to reproduce it, and the version or commit you tested. If you run your own install, say so.

This covers the code in this repository and the hosted service at mainline.dev. Fixes go to `master`, so run the latest commit to get them.

There is no bug bounty.

## How teams are kept apart

Every table that holds a team's data has a Postgres row-level security policy. Each request sets the current team (`app.current_team_id`) inside its transaction, through `SetTeamContext`, and the policies return only that team's rows. The app connects as `mainline_app`, a role the policies apply to.

This is defence in depth. It catches application code that forgets to scope a query. It does not hold against someone who can run their own SQL as `mainline_app`, because that role sets the same settings the policies read. Keeping SQL injection out is what protects against that: queries go through Sequel with bound parameters, and request input is never pasted into SQL.

A few places turn the policies off for one block with `BypassRLS.call`, each for a narrow reason, such as background jobs that work across teams, a GitHub webhook after its signature is checked, an invitation looked up by its token, and a map loaded by its ID before the person's membership of its team is checked. `grep -rn "BypassRLS.call" lib routes app.rb models` lists them. A pull request that adds one should say why the query can't run inside a team's context.
