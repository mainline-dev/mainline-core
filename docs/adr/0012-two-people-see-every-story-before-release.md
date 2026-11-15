# Two people see every story before release

## Context and Problem Statement

A story starts with two people by default, and a team can
allow one person to start it. Teams working with coding
agents often work solo. Mainline works without pull
requests, so a solo story could reach users seen by one
person only.

## Considered Options

- Pull requests that gate merging
- A second person sees each story before release
- No rule, with solo shown in red and listed in the solo log

## Decision Outcome

Review gates release. Merging and deploying stay ungated, so
work reaches the mainline and production as often as before,
behind its decoupling strategy.

Two people have seen a story when two or more were on it at
any time while it was active, or when a walkthrough is
recorded. Both are events on the story (ADR 0008), so there
is no new table and no new row level security.

The number of stories awaiting a walkthrough is a team
constraint, checked under the team's lock in the transaction
that starts a story, as the WIP limit is.

### Consequences

Deployed solo stories queue for a walkthrough, and the limit
stops new work until someone walks them through. Pairing for
a minute meets the rule, and the assignment shows in the
story's history. Teams of one are exempt. The rule is on by
default. Turning it off, or changing the limit, needs a
reason, which the settings history shows.

### Left out

A computed walkthrough agenda (commit links, scenario
results, check findings) and a release gate on feature
flags. The export is unchanged: walkthroughs and kickoffs are
in its event record already, and `format_version` stays as
it is.
