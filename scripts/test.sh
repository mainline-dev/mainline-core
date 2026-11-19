#!/usr/bin/env bash
set -euo pipefail
# Contributors' stack; docker-compose.yml is the quick start's trial.
export COMPOSE_FILE=docker-compose.dev.yml

DUMMY_KEY="0000000000000000000000000000000000000000000000000000000000000000"
# The sign-in tests need every provider present; the development compose ships them disabled.
# Tests get their own Redis database, or the dev worker takes the jobs they queue.
TEST_ENV=(-e RACK_ENV=test -e REDIS_URL=redis://redis:6379/1 -e LOCKBOX_MASTER_KEY="$DUMMY_KEY" -e GOOGLE_CLIENT_ID=test -e GOOGLE_CLIENT_SECRET=test -e GH_OAUTH_CLIENT_ID=test -e GH_OAUTH_CLIENT_SECRET=test -e GITLAB_CLIENT_ID=test -e GITLAB_CLIENT_SECRET=test)

docker compose exec -T "${TEST_ENV[@]}" app bundle exec rake test_up
echo "Running linter..."
docker compose exec -T "${TEST_ENV[@]}" app bundle exec rubocop
echo "Running model and acceptance tests..."
docker compose exec -T "${TEST_ENV[@]}" app bundle exec rake default

echo "Running browser tests (requires Chrome on host)..."
scripts/browser_test.sh

# Not a gate: it lists the tests made weaker since origin/master, for a
# person to read. Given one commit, Slopbouncer compares the working tree
# with it, so it reads the commits waiting to be pushed and any change not
# yet committed: a run made before the commit sees the change it is testing.
# It only reads the code, so it comes before the slow stage below.
GIT_IN_APP=(-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/app)
# It runs in the container and cannot see this terminal, so tell it when
# there is one: it then groups its findings by file, in colour.
SLOPBOUNCER_COLOUR=""
if [ -t 1 ]; then SLOPBOUNCER_COLOUR="--color"; fi
echo "Tests that look weaker since origin/master (Slopbouncer)..."
docker compose exec -T "${GIT_IN_APP[@]}" app bundle exec slopbouncer origin/master $SLOPBOUNCER_COLOUR

# Not a gate on the score: it shows what survives in the classes this push
# changes, and stops only when one of them has got worse than its baseline.
echo "Mutation testing the classes changed since origin/master..."
docker compose exec -T "${TEST_ENV[@]}" "${GIT_IN_APP[@]}" app bundle exec rake mutant_changed
