# Mainline

Mainline is project tooling for teams that practise continuous integration and continuous delivery. Work lives on a user story map instead of a backlog: activities across the top, releases sliced down in priority order. Each person has one active story at a time, enforced by the system. Deploy and release are separate events with separate buttons, so nothing is called done until users have it. There are no story points, no sprints and no individual metrics. Every change is an immutable event and the whole team sees the same views: the map, flow, teamwork and inventory. The CI Monitor shows how long each branch has lived on every connected GitHub repo.

Documentation and practice guides: https://mainline.dev/docs

## Quick start

You need Docker with Compose.

```shell
git clone https://github.com/mainline-dev/mainline-core.git
cd mainline-core
docker compose up --build
```

The app runs at http://localhost:3000. `docker-compose.yml` is the development setup and carries its own throwaway values, so no configuration is needed. Sign up with an email address; the Google, GitHub and GitLab buttons appear once their variables hold real OAuth apps.

Load sample teams and print a login link for each person:

```shell
docker compose exec app bundle exec rake dev_seed
```

## Self-host

`docker-compose.selfhost.yml` runs the app, a Sidekiq worker, Postgres and Redis with `RACK_ENV=production`. Every variable is required and has no default. Set them in your shell, or in a `.env` file next to the compose file, then:

```shell
docker compose -f docker-compose.selfhost.yml up -d --build
```

| Variable | Purpose |
|---|---|
| `POSTGRES_PASSWORD` | Password for the `mainline` database owner |
| `MAINLINE_APP_USER_DATABASE_PASSWORD` | Password for the `mainline_app` role the app connects as (row-level security applies to it) |
| `MAINLINE_SESSION_SECRET` | Session cookie secret, at least 64 random characters (`openssl rand -hex 32`) |
| `LOCKBOX_MASTER_KEY` | 64 hex characters used to encrypt email addresses at rest (`openssl rand -hex 32`) |
| `BASE_URL` | Public URL of the app, for example `https://mainline.example.org` |
| `MAINLINE_HOST` | Host name of the app, for example `mainline.example.org` |
| `SMTP_HOST` | Mail server host name |
| `SMTP_PORT` | Mail server port, usually 587 |
| `SMTP_USERNAME` | Mail server user name |
| `SMTP_PASSWORD` | Mail server password |
| `SMTP_TLS` | `starttls` (port 587) or `tls` (encrypted from the start, port 465) |
| `MAIL_FROM` | Sender for all email, for example `Mainline <noreply@example.org>` |
| `GOOGLE_CLIENT_ID` | Google sign-in client ID; `disabled` leaves Google sign-in out |
| `GOOGLE_CLIENT_SECRET` | Google sign-in client secret |
| `GH_OAUTH_CLIENT_ID` | GitHub sign-in client ID; `disabled` leaves GitHub sign-in out |
| `GH_OAUTH_CLIENT_SECRET` | GitHub sign-in client secret |
| `GITLAB_CLIENT_ID` | GitLab sign-in client ID; `disabled` leaves GitLab sign-in out |
| `GITLAB_CLIENT_SECRET` | GitLab sign-in client secret |
| `CI_MONITOR_GITHUB_APP_ID` | CI Monitor GitHub App ID |
| `CI_MONITOR_GITHUB_APP_SLUG` | CI Monitor GitHub App URL name, used for the install link |
| `CI_MONITOR_GITHUB_APP_CLIENT_ID` | CI Monitor GitHub App client ID |
| `CI_MONITOR_GITHUB_APP_CLIENT_SECRET` | CI Monitor GitHub App client secret |
| `CI_MONITOR_GITHUB_PRIVATE_KEY` | CI Monitor GitHub App private key (PEM) |
| `CI_MONITOR_GITHUB_WEBHOOK_SECRET` | CI Monitor GitHub App webhook signing secret |
| `SENTRY_DSN` | Sentry DSN for error reports; a plain word such as `disabled` turns sending off |
| `SENTRY_ENVIRONMENT` | Label on error reports, for example `production` |

## Running the tests

The suite runs inside Docker. With the development stack up:

```shell
scripts/test.sh
```

It migrates the test database, runs RuboCop, then the model and acceptance tests in Docker, then the browser tests on the host (they need Chrome).

## Licence

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).
