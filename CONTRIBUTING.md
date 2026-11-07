# Contributing

Mainline is built the way it asks teams to work.

- Trunk-based. Branch from `master`, keep the branch short-lived.
- Small commits. One behaviour per commit, each one leaving the suite green.
- Tests first. Every change in behaviour comes with a test that failed before the change. Tests describe behaviour, not implementation details.
- Run the full suite before opening a pull request: `scripts/test.sh`. Turn on the pre-push hook once after cloning, and it runs for you: `git config core.hooksPath scripts/hooks`.
- RuboCop violations are fixed in the code. Pull requests that add exclusions to `.rubocop.yml` will be asked to refactor instead.
- New tables with a `team_id` need row-level security, cleanup in `lib/delete_team.rb` and indexes for their query patterns.

Pull requests that add story points, sprints, velocity or individual metrics will be closed.

Before your first pull request can be merged, you sign the [contributor licence agreement](CLA.md); a bot asks you on the pull request. You keep the copyright in your work. Mainline's hosted service includes private code, so the agreement lets Kipple PTY LTD use your contribution there as well as in this repository, which stays under the GNU Affero General Public License v3.0.
