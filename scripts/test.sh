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
export TEST_DATABASE_URL=postgres://mainline:password@localhost:5432/mainline_test
export TEST_APP_DATABASE_URL=postgres://mainline_app:app_password@localhost:5432/mainline_test
export MAINLINE_SESSION_SECRET=0000000000000000000000000000000000000000000000000000000000000000
export MAINLINE_HOST=localhost:3000
export LOCKBOX_MASTER_KEY=0000000000000000000000000000000000000000000000000000000000000000
export REDIS_URL=redis://localhost:6379/1
export SENTRY_DSN=test
export SENTRY_ENVIRONMENT=test
export CI_MONITOR_GITHUB_APP_ID=test
export CI_MONITOR_GITHUB_APP_SLUG=test
export CI_MONITOR_GITHUB_APP_CLIENT_ID=test
export CI_MONITOR_GITHUB_APP_CLIENT_SECRET=test
export CI_MONITOR_GITHUB_PRIVATE_KEY=test
export CI_MONITOR_GITHUB_WEBHOOK_SECRET=test
export SMTP_HOST=test
export SMTP_PORT=465
export SMTP_USERNAME=test
export SMTP_PASSWORD=test
export SMTP_TLS=tls
export MAIL_FROM=test@localhost
export GOOGLE_CLIENT_ID=test
export GOOGLE_CLIENT_SECRET=test
export GH_OAUTH_CLIENT_ID=test
export GH_OAUTH_CLIENT_SECRET=test
export GITLAB_CLIENT_ID=test
export GITLAB_CLIENT_SECRET=test
export BASE_URL=http://localhost:3000
export RACK_ENV=test
bundle exec rake test_browser
