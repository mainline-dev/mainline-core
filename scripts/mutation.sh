#!/usr/bin/env bash
# Mutation testing, class by class, in the test stack. Writes each class's
# score to .mutant-baseline.yml. All classes take about a quarter of an hour;
# name some to measure only those again:
#
#   scripts/mutation.sh AssignPerson DataExport
#
# It uses the test database, so do not run it alongside scripts/test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

DUMMY_KEY="0000000000000000000000000000000000000000000000000000000000000000"
TEST_ENV=(-e RACK_ENV=test -e REDIS_URL=redis://redis:6379/1 -e LOCKBOX_MASTER_KEY="$DUMMY_KEY" -e GOOGLE_CLIENT_ID=test -e GOOGLE_CLIENT_SECRET=test -e GH_OAUTH_CLIENT_ID=test -e GH_OAUTH_CLIENT_SECRET=test -e GITLAB_CLIENT_ID=test -e GITLAB_CLIENT_SECRET=test)

docker compose exec -T "${TEST_ENV[@]}" app bundle exec rake test_up
docker compose exec -T "${TEST_ENV[@]}" app bundle exec rake "mutant_baseline[$*]"
