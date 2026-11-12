#!/usr/bin/env bash
set -euo pipefail

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

# Not a gate on the score: it shows what survives in the classes this push
# changes, and stops only when one of them has got worse than its baseline.
echo "Mutation testing the classes changed since origin/master..."
docker compose exec -T "${TEST_ENV[@]}" -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/app app bundle exec rake mutant_changed
