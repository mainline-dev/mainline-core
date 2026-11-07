#!/usr/bin/env bash
set -euo pipefail

# The sign-in tests need every provider present; the development compose ships them disabled.
# Tests get their own Redis database, or the dev worker takes the jobs they queue.
TEST_ENV=(-e RACK_ENV=test -e REDIS_URL=redis://redis:6379/1 -e GOOGLE_CLIENT_ID=test -e GOOGLE_CLIENT_SECRET=test -e GH_OAUTH_CLIENT_ID=test -e GH_OAUTH_CLIENT_SECRET=test -e GITLAB_CLIENT_ID=test -e GITLAB_CLIENT_SECRET=test)

docker compose run --rm "${TEST_ENV[@]}" app bundle exec rake test_up
docker compose run --rm "${TEST_ENV[@]}" app bundle exec rake default
