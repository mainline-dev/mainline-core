#!/usr/bin/env bash
# The browser tests, run on the host against the test database and Redis the
# compose stack publishes. Needs Chrome, Ruby and the bundle on the host, and
# the stack's db and redis up. scripts/test.sh runs this last on a developer's
# machine, and CI runs it in a job of its own, so both run the same thing.
set -euo pipefail
cd "$(dirname "$0")/.."

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
export SIGNUPS=open
export RACK_ENV=test

bundle exec rake test_up
bundle exec rake test_browser
