# Mainline stack tutorial

How to add features to this codebase, starting from an acceptance test.

## The test architecture

This project uses Dave Farley's 4-tier test structure:

```
test/acceptance/test_*.rb     - acceptance tests (describe WHAT the system does)
  ↓ calls
test/dsl/mainline_dsl.rb      - domain DSL (business-language methods)
  ↓ calls
test/dsl/drivers/*_driver.rb  - drivers (HOW the action is performed: HTTP or browser)
  ↓ hits
routes/*.rb → models/*.rb     - production code
```

Acceptance tests never touch HTTP or Rack directly. They call DSL methods like `create_persona('Alice')`. The DSL delegates to a **driver** -  `HttpDriver` (Rack::Test, fast, default) or `BrowserDriver` (Capybara, for JS/HTMX). Same test, swappable transport.

Model tests (`test/models/test_*.rb`) test database constraints and model behaviour in isolation -  no app, no routes.

## Running the tests

Everything runs inside Docker:

```sh
# All tests (lint + model + acceptance)
docker compose exec -e RACK_ENV=test app bundle exec rake default

# Only model tests
docker compose exec -e RACK_ENV=test app bundle exec rake test_models

# Only acceptance tests
docker compose exec -e RACK_ENV=test app bundle exec rake test_acceptance

# Bounce test DB (down + up -  use after changing migrations)
docker compose exec -e RACK_ENV=test app bundle exec rake test_bounce
```

## Walkthrough: adding "archive persona"

We'll add the ability to archive a persona. The persona stays in the database but disappears from the map. An event is recorded. We work outside-in: acceptance test first, then fill in each layer until it passes.

### Step 1 -  write the acceptance test

Open `test/acceptance/test_map_structure.rb`. Add a new describe block:

```ruby
describe 'archiving' do
  it 'removes an archived persona from the map view' do
    visitor = create_persona('Visitor')
    assert_map_shows 'Visitor'

    archive_persona(visitor)

    assert_map_does_not_show 'Visitor'
    assert_event_recorded(entity: visitor, action: 'archived')
  end
end
```

This calls `archive_persona` -  a DSL method that doesn't exist yet. Run the tests:

```sh
docker compose exec -e RACK_ENV=test app bundle exec rake test_acceptance
```

It fails with `NoMethodError: undefined method 'archive_persona'`. Good.

### Step 2 -  add the DSL method

Open `test/dsl/mainline_dsl.rb`. Add under the domain actions section:

```ruby
def archive_persona(persona)
  driver.submit_archive_persona(@map, persona_id: persona.id)

  persona.refresh
  refute_nil persona.archived_at, "Persona '#{persona.name}' was not archived"
  assert_event_recorded(entity: persona, action: 'archived')

  persona
end
```

The pattern: call the driver, then verify model state and event side-effects.

Run again -  now it fails with `NoMethodError: undefined method 'submit_archive_persona'` on the driver. Progress.

### Step 3 -  add the driver methods

**HTTP driver** (`test/dsl/drivers/http_driver.rb`):

```ruby
def submit_archive_persona(map, attrs)
  post "/maps/#{map.id}/personas/#{attrs[:persona_id]}/archive"
  last_response
end
```

**Browser driver** (`test/dsl/drivers/browser_driver.rb`):

```ruby
def submit_archive_persona(map, attrs)
  visit "/maps/#{map.id}"
  within '.persona-list' do
    click_on 'Archive'  # whatever your UI label is
  end
end
```

Run again -  now it returns a 404 because the route doesn't exist.

### Step 4 -  add the route

Open `routes/maps.rb`. Inside the `r.on 'personas'` block, add a sub-route:

```ruby
r.on 'personas' do
  append_view_subdir('personas')

  # ... existing GET new / POST routes ...

  r.on String do |persona_id|
    @persona = Persona[persona_id]
    next unless @persona

    r.post 'archive' do
      DB.transaction do
        @persona.update(archived_at: Time.now)
        RecordEvent.call(
          actor_id:     @current_person.id,
          entity:       @persona,
          action:       'archived',
          before_state: { archived_at: nil },
          after_state:  { archived_at: @persona.archived_at.iso8601 }
        )
      end
      flash[:notice] = "Persona '#{@persona.name}' archived"
      r.redirect "/maps/#{@map.id}"
    end
  end
end
```

Run the acceptance tests -  they should pass now. The map view already filters by `archived_at: nil` (look at `routes/maps.rb` lines 14 and 70), so the archived persona disappears automatically.

### Step 5 -  add a model test (if needed)

If there's a database constraint or model-level behaviour worth testing (e.g. "archiving a persona doesn't orphan its activities"), add it in `test/models/`:

```ruby
# test/models/test_persona_archive.rb
require_relative '../model_spec_helper'

describe 'Archiving a persona' do
  before do
    @team = Team.create(name: 'Test')
    @map  = Map.create(team_id: @team.id, name: 'Map', position: 1000)
  end

  it 'sets archived_at without deleting the row' do
    persona = Persona.create(
      map_id: @map.id, team_id: @team.id, name: 'Visitor', position: 1000
    )
    persona.update(archived_at: Time.now)
    refute_nil Persona[persona.id]
    refute_nil persona.refresh.archived_at
  end
end
```

Model tests require `model_spec_helper` (loads models only, no app or routes).

### Step 6 -  run green

```sh
docker compose exec -e RACK_ENV=test app bundle exec rake default
```

All tests pass. The cycle is: acceptance test (red) → DSL → driver → route → model test → green.

## Key patterns

### Transaction wrapping in tests

`test/test_helper.rb` sets up two levels of rollback:

```ruby
# Outer: wraps the entire describe block -  shared `before` data lives here
around(:all) do |&block|
  DB.transaction(rollback: :always) { super(&block) }
end

# Inner: wraps each `it` block in a savepoint -  each test is isolated
around do |&block|
  DB.transaction(rollback: :always, savepoint: true, auto_savepoint: true) { super(&block) }
end
```

Nothing persists. The test database stays clean without truncation or seeding.

### Debug logging

Wrap any code in the `log` helper to see SQL queries:

```ruby
it 'creates an event' do
  log do
    create_persona('Debug me')
  end
end
```

This temporarily sets `LOGGER.level = Logger::INFO` then restores it.

### RecordEvent

Every mutation records an event. Call inside a `DB.transaction`:

```ruby
DB.transaction do
  @persona = Persona.create(...)
  RecordEvent.call(
    actor_id:    @current_person.id,
    entity:      @persona,
    action:      'created',
    after_state: { name: @persona.name, position: @persona.position }
  )
end
```

For multi-step operations, use a `correlation_id` to link events:

```ruby
correlation = SecureRandom.uuid

persona_ids.each do |pid|
  ActivityPersona.create(...)
  RecordEvent.call(
    actor_id: @current_person.id, entity: @activity,
    action: 'persona_added', after_state: { persona_id: pid },
    correlation_id: correlation
  )
end

RecordEvent.call(
  actor_id: @current_person.id, entity: @activity,
  action: 'created', after_state: { name: name },
  correlation_id: correlation
)
```

### Testing deferred constraints

PostgreSQL deferred constraints only fire at `COMMIT`, but tests never commit (everything rolls back). Force the check inside a savepoint:

```ruby
it 'cannot remove the last persona from an activity' do
  activity = create_activity_with_persona

  assert_raises(Sequel::DatabaseError) do
    DB.transaction(savepoint: true) do
      ActivityPersona.where(activity_id: activity.id).delete
      DB.run 'SET CONSTRAINTS ALL IMMEDIATE'
    end
  end
end
```

### Driver swapping

Tests default to `HttpDriver`. To use the browser driver for a specific test:

```ruby
before do
  use_browser!
end
```

The DSL handles the difference. The `create_activity` DSL method, for example, sends `persona_ids` (UUIDs) to the HTTP driver but `persona_names` (text) to the browser driver, because Capybara checks checkboxes by label.

### View subdirectories

The `hash_branch_view_subdir` plugin automatically appends the branch name to the view path. Sub-branches in `routes/maps/*.rb` use `hash_branch('maps', 'personas')` -  the plugin stacks `maps` then `personas`, so `view 'new'` resolves to `views/maps/personas/new.erb`:

```ruby
# routes/maps/personas.rb
hash_branch('maps', 'personas') do |r|
  # view subdir is automatically 'maps/personas'

  r.get 'new' do
    view 'new'   # resolves to views/maps/personas/new.erb
  end
end
```

No manual `append_view_subdir` calls needed. If your view name contains a `/`, the plugin assumes it's already a full path and won't prepend the subdirectory.

## Authentication

Mainline uses OAuth (Google + GitHub) via OmniAuth. Session-based: after OAuth callback, `person_id` is stored in an encrypted Roda session cookie.

### Local development

Set up one or both OAuth providers:

**GitHub** (~2 minutes):
1. https://github.com/settings/developers → New OAuth App
2. Application name: `Mainline Dev`
3. Homepage URL: `http://localhost:3000`
4. Authorization callback URL: `http://localhost:3000/auth/github/callback`
5. Leave "Device Flow" unchecked
6. Copy Client ID and generate a Client Secret

**Google** (~5 minutes):
1. https://console.cloud.google.com → create or select a project
2. APIs & Services → OAuth consent screen → External → add your email as test user
3. APIs & Services → Credentials → Create Credentials → OAuth Client ID → Web application
4. Authorized redirect URI: `http://localhost:3000/auth/google_oauth2/callback`
5. Copy Client ID and Client Secret

Export the credentials before starting the app:

```sh
export GITHUB_CLIENT_ID=Ov23li...
export GITHUB_CLIENT_SECRET=...
export GOOGLE_CLIENT_ID=12345-xxx.apps.googleusercontent.com
export GOOGLE_CLIENT_SECRET=GOCSPX-...
docker compose up -d app
```

These are passed into the container via `docker compose`. Each provider works independently -  you only need one.

Visit http://localhost:3000/login and click either button. After OAuth, you'll be redirected to `/teams`. If you have no team yet, create one at `/teams/new`.

### Production (mainline.dev)

Same setup, different redirect URIs:
- GitHub callback: `https://mainline.dev/auth/github/callback`
- Google redirect URI: `https://mainline.dev/auth/google_oauth2/callback`

Set the four env vars the same way you set `MAINLINE_SESSION_SECRET` in Kamal.

### Tests

Tests don't use OAuth. The `_test_login` endpoint (test-only) sets the session directly:

```ruby
# In HttpDriver
def login_as(person)
  post '/_test_login', { 'person_id' => person.id }
end
```

The DSL's `add_person` auto-logs-in the first person added. Subsequent calls to `login_as` switch identity.

### Dev seed

The seed script (`MAINLINE_SEED=1`) bypasses auth entirely -  no session or OAuth needed. The `seeding?` guard in `app.rb` only activates when `RACK_ENV=development && MAINLINE_SEED` is set, so it cannot accidentally run in production.

To reset and re-seed the dev database:

```sh
# Basic: wipe DB, migrate, seed
./scripts/bounce_seed.sh

# With your OAuth email: injects you as a working member on all seed teams
./scripts/bounce_seed.sh you@example.com
```

The email version finds-or-creates your person and adds them to every team, so OAuth login matches you immediately.

## Rake cheatsheet

| Task | Description |
|------|-------------|
| `rake default` | Lint + model/lib tests + acceptance tests |
| `rake lint` | Run RuboCop |
| `rake test_models` | Run `test/models/test_*.rb` + `test/lib/test_*.rb` |
| `rake test_acceptance` | Run `test/acceptance/test_*.rb` |
| `rake test_browser` | Run `test/browser/test_*.rb` (requires Chrome on host) |
| `rake test_cov` | All tests with SimpleCov coverage |
| `rake test_models_cov` | Model/lib tests with coverage |
| `rake test_acceptance_cov` | Acceptance tests with coverage |
| `rake test_up` | Migrate test DB to latest |
| `rake test_down` | Migrate test DB to version 0 |
| `rake test_bounce` | Down then up (use after editing migrations) |
| `rake dev_up` / `dev_down` / `dev_bounce` | Same for development DB |
| `rake prod_up` | Migrate production DB to latest |
| `rake dev_seed` | Seed development database with sample team history |
| `rake dev_teardown` | Remove seed data from development database |
| `rake screenshot_seed` | Seed a compact team for map screenshots |
| `rake demo_refresh` | Shift demo team timestamps to present |
| `rake export[team_id]` | Export team data as JSON |
| `rake test_irb` | IRB with models loaded in test mode |
| `rake dev_irb` | IRB in development mode |
| `rake prod_irb` | IRB in production mode |
| `rake mutant` | Run mutation testing on all lib and model code |
| `rake mutant_one[Subject]` | Run mutation testing on a single class |
| `rake mutant_rls` | Run mutation testing on RLS code |
| `rake annotate` | Add schema comments to model files |

## File map

```
app.rb                             Roda app (plugins, route entry point)
db.rb                              Database connection setup
routes/auth.rb                     OAuth login/logout
routes/maps.rb                     /maps/:id show + dispatch to sub-branches
routes/maps/*.rb                   Per-resource routes (personas, activities, tasks, stories, release_slices)
routes/teams.rb                    Team management + dispatch to sub-branches
routes/teams/*.rb                  Per-feature routes (flow, inventory, teamwork, monitor, webhook, account)
routes/api.rb                      JSON API endpoints
routes/webhooks/*.rb               Webhook handlers, one file per sender
models/*.rb                        Sequel models (24 files)
lib/*.rb                           Service objects, presenters, helpers (37 files)
views/layout.erb                   Master layout (HTMX, CSS)
views/maps/show.erb                Map view
views/teams/show.erb               Team dashboard
views/docs/*.erb                   Public documentation pages
migrate/*.rb                       Schema migrations (001-075)
test/test_helper.rb                Transaction wrapping (minitest-hooks)
test/model_spec_helper.rb          Model + lib test loader
test/web_spec_helper.rb            Acceptance test loader (app + Rack::Test)
test/dsl/mainline_dsl.rb           Domain DSL
test/dsl/drivers/http_driver.rb    Rack::Test driver
test/dsl/drivers/browser_driver.rb Capybara driver
test/models/test_*.rb              Model tests (DB constraints, validations)
test/lib/test_*.rb                 Lib tests (service objects, presenters)
test/acceptance/test_*.rb          Acceptance tests (HTTP-driven, Docker)
test/browser/test_*_browser.rb     Browser tests (Capybara + Chrome, host)
```
