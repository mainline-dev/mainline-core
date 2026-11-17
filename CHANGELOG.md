# Changelog

What changed in Mainline, by month.

## November 2026

- Mainline's core is published as open source under the AGPL v3, and `docker compose up` starts a local trial with sample teams.
- Self-hosted installs can close sign-ups to the first person and their invitees, and can run without the CI Monitor.
- Ticket Museum: import a Jira CSV export, preview it, then promote tickets onto the map one at a time as stories with scenarios, or let go of the stale, duplicate and vague tickets the curator suggests.
- A specification can come into the museum as a Mainline file of proposed stories, checked against a published schema, and a coding agent can ask Mainline how to write one.
- A team can raise its limit on active stories per person, with a reason everyone sees in its history.
- Scenarios have names, and each story's scenarios download as a Gherkin feature file with step stubs for Kotlin, Java, Ruby, TypeScript or Python, which coding agents can also fetch over MCP.
- Any member can download everything the team has as one zip: the stories in map order with feature files, a CSV that Jira or another team's museum can import, the museum, and the full record as JSON.
- By default two people see every story before release: a story worked on alone needs a recorded walkthrough, waiting stories are listed on a Walkthroughs page, and a team can turn the rule off with a reason.
- A kickoff shows when someone other than the last editor has agreed a solo story's scenarios. It is shown and never enforced.
- Each release slice offers Markdown release notes listing its released stories with their scenarios.
- A story can be started as urgent with a reason, one per team at a time. It sits outside the limit on active stories and can be released before its walkthrough.
- A story with no scenarios can't be released unless someone logs a reason. An urgent story needs none.
- Coding agents connect with personal tokens, which each person makes and revokes for the teams they can open. Each read is logged against its person and leaves the story unchanged.
- Security fixes, released in v0.2.0 and v0.2.1.

## October 2026

- Sign-in links, verification and invitation emails go through any SMTP server set in the environment.

## July 2026

- Scenarios can be ticked done, release waits until every scenario is done, and unfinished scenarios can be split off into a new story placed after the original.
- The map can be filtered to one release slice, and the filter stays set for that person.
- Story cards show an agent chip once a coding agent has read the story, and each read appears in its history.

## June 2026

- Sign up and sign in with an email address and password or a magic link, reset a forgotten password, and verify the address before creating a team.
- A read-only MCP server lets a coding agent read the team's maps and stories with their scenarios.
- Maps and personas can be archived, and a team can be renamed.
- A person who has left their teams can delete their account, and the events they made stay in the history.
- A team can choose the template its new stories start from.
- The CI Monitor syncs connected repositories in the background and can filter them by organisation.

## May 2026

- The CI Monitor connects to GitHub repositories and shows each branch's age and status, leaving out weekends.
- A team sets a branch age goal and can mark throwaway branches as spikes, which are flagged if they are later merged.
- The CI Monitor shows a daily streak heatmap with average, maximum and pooled p90 summaries.
- The CI Monitor works across several GitHub organisations and uses the team's timezone.
- Sign in with GitLab, link several sign-in accounts to one person, and edit your profile.
- Story cards flag split candidates, stale stories, stale solo work and stale feature flags.
- Keyboard shortcuts move between views.

## April 2026

- A team works on story maps of activities, steps and stories, with personas, ordered into release slices and rearranged by drag and drop.
- Each person works on one active story at a time. A story becomes active once a second person joins, unless the team allows solo starts.
- Every change is an event, shown in the history of each story, activity, persona, slice and map.
- Deploy and release are separate events: a pipeline marks stories deployed through a webhook, release needs a deploy first, and released stories can't be changed.
- Each story records how its deploy is kept apart from its release (feature flag, branch by abstraction or dark launch), and inventory lists the flags left to clean up after release.
- The flow view shows cumulative flow, deploy and release throughput, and lead time to release.
- The teamwork view shows the pairing matrix, ensembles and solo work, and the inventory view lists deployed stories waiting for release, marked aging or stale.
- Stories active longer than most of the team's released stories are flagged as split candidates, and team settings control the percentile and the aging and stale thresholds.
- Stories carry acceptance scenarios in Given/When/Then form and can start from a user story template.
- People sign in with Google or GitHub and join a team by email invitation.
- Tasks, activities and team members can be archived, and the account holder can export the team's data or delete the team.
