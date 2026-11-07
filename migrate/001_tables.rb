# frozen_string_literal: true

Sequel.migration do
  up do
    run "CREATE EXTENSION IF NOT EXISTS pgcrypto"
    run "CREATE EXTENSION IF NOT EXISTS citext"

    # -- TEAMS & BILLING ------------------------------

    create_table(:teams) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      String :name, null: false
      String :timezone, null: false, default: 'UTC'

      String :stripe_customer_id, unique: true
      String :stripe_subscription_id, unique: true
      String :subscription_status, null: false, default: 'trialing'
      column :trial_starts_at, 'timestamptz'
      column :trial_ends_at, 'timestamptz'
      Integer :price_cents, null: false, default: 20000
      column :currency, 'char(3)', null: false, default: 'USD'

      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      constraint(:valid_subscription_status) do
        Sequel.lit("subscription_status IN ('trialing', 'active', 'past_due', 'canceled')")
      end
    end

    # -- PEOPLE & AUTH --------------------------------

    create_table(:people) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      String :name, null: false
      column :email, 'citext', null: false, unique: true
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    create_table(:person_identities) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :person_id, :people, type: :uuid, null: false, on_delete: :cascade
      String :provider, null: false
      String :provider_subject, null: false
      column :email, 'citext', null: false
      String :password_digest

      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      unique [:provider, :provider_subject]
      index :person_id, name: :idx_identities_person
    end

    # -- TEAM MEMBERSHIPS -----------------------------

    create_table(:team_memberships) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      foreign_key :person_id, :people, type: :uuid, null: false
      column :joined_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :left_at, 'timestamptz'

      unique [:team_id, :person_id]
    end

    run "CREATE INDEX idx_memberships_team   ON team_memberships (team_id)   WHERE left_at IS NULL"
    run "CREATE INDEX idx_memberships_person ON team_memberships (person_id) WHERE left_at IS NULL"

    # -- INVITATIONS ----------------------------------

    create_table(:invitations) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      column :email, 'citext', null: false
      String :token, null: false, unique: true
      foreign_key :invited_by, :people, type: :uuid, null: false
      column :expires_at, 'timestamptz', null: false
      column :accepted_at, 'timestamptz'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run "CREATE INDEX idx_invitations_team ON invitations (team_id) WHERE accepted_at IS NULL"

    # -- TEAM CONSTRAINTS -----------------------------

    create_table(:team_constraints) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :constraint_key, null: false
      Integer :value, null: false
      Integer :min_value, null: false
      Integer :max_value, null: false
      Integer :default_value, null: false
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      unique [:team_id, :constraint_key]
      constraint(:valid_constraint_range) { Sequel.lit("value >= min_value AND value <= max_value") }
    end

    # -- TEAM HOLIDAYS --------------------------------

    create_table(:team_holidays) do
      foreign_key :team_id, :teams, type: :uuid, null: false
      Date :holiday_date, null: false
      String :name, null: false
      primary_key [:team_id, :holiday_date]
    end

    # -- MAPS -----------------------------------------

    create_table(:maps) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :name, null: false
      Integer :position, null: false
      column :archived_at, 'timestamptz'
      Integer :lock_version, null: false, default: 0
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run "ALTER TABLE maps ADD CONSTRAINT uq_maps_position UNIQUE (team_id, position) DEFERRABLE INITIALLY DEFERRED"
    run "CREATE INDEX idx_maps_team_active ON maps (team_id) WHERE archived_at IS NULL"

    # 10-map cap trigger
    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_map_cap()
      RETURNS TRIGGER AS $$
      DECLARE
          active_count integer;
      BEGIN
          SELECT COUNT(*) INTO active_count
          FROM maps
          WHERE team_id = NEW.team_id
            AND archived_at IS NULL;

          IF active_count >= 10 THEN
              RAISE EXCEPTION 'Team has reached the maximum of 10 active maps';
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE TRIGGER check_map_cap
          BEFORE INSERT OR UPDATE OF archived_at ON maps
          FOR EACH ROW
          WHEN (NEW.archived_at IS NULL)
          EXECUTE FUNCTION enforce_map_cap();
    SQL

    # -- PERSONAS (extension) -------------------------

    create_table(:personas) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :map_id, :maps, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :name, null: false
      String :description, null: false, default: ''
      Integer :position, null: false
      column :archived_at, 'timestamptz'
      Integer :lock_version, null: false, default: 0
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run "ALTER TABLE personas ADD CONSTRAINT uq_personas_position UNIQUE (map_id, position) DEFERRABLE INITIALLY DEFERRED"

    # -- ACTIVITIES -----------------------------------

    create_table(:activities) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :map_id, :maps, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :name, null: false
      Integer :position, null: false
      column :archived_at, 'timestamptz'
      Integer :lock_version, null: false, default: 0
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run "ALTER TABLE activities ADD CONSTRAINT uq_activities_position UNIQUE (map_id, position) DEFERRABLE INITIALLY DEFERRED"

    # -- ACTIVITY_PERSONAS (join table with enforcement) --

    create_table(:activity_personas) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :activity_id, :activities, type: :uuid, null: false
      foreign_key :persona_id, :personas, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false

      unique [:activity_id, :persona_id]
    end

    # Trigger: prevent removing the last persona from an activity
    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_min_one_persona()
      RETURNS TRIGGER AS $$
      DECLARE
          remaining integer;
      BEGIN
          SELECT COUNT(*) INTO remaining
          FROM activity_personas
          WHERE activity_id = OLD.activity_id;

          IF remaining = 0 THEN
              RAISE EXCEPTION 'Activity must have at least one persona';
          END IF;

          RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE CONSTRAINT TRIGGER check_min_one_persona
          AFTER DELETE ON activity_personas
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION enforce_min_one_persona();
    SQL

    # Trigger: prevent creating an activity without any persona (deferred check)
    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_activity_has_persona()
      RETURNS TRIGGER AS $$
      DECLARE
          persona_count integer;
      BEGIN
          SELECT COUNT(*) INTO persona_count
          FROM activity_personas
          WHERE activity_id = NEW.id;

          IF persona_count = 0 THEN
              RAISE EXCEPTION 'Activity must have at least one persona';
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE CONSTRAINT TRIGGER check_activity_has_persona
          AFTER INSERT ON activities
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION enforce_activity_has_persona();
    SQL

    # -- TASKS ----------------------------------------

    create_table(:tasks) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :activity_id, :activities, type: :uuid, null: false
      foreign_key :map_id, :maps, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :name, null: false
      Integer :position, null: false
      column :archived_at, 'timestamptz'
      Integer :lock_version, null: false, default: 0
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run "ALTER TABLE tasks ADD CONSTRAINT uq_tasks_position UNIQUE (activity_id, position) DEFERRABLE INITIALLY DEFERRED"

    # -- RELEASE SLICES -------------------------------

    create_table(:release_slices) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :map_id, :maps, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :name, null: false
      Integer :position, null: false
      column :archived_at, 'timestamptz'
      Integer :lock_version, null: false, default: 0
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run "ALTER TABLE release_slices ADD CONSTRAINT uq_slices_position UNIQUE (map_id, position) DEFERRABLE INITIALLY DEFERRED"

    # -- STORIES --------------------------------------

    create_table(:stories) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :task_id, :tasks, type: :uuid, null: false
      foreign_key :map_id, :maps, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      foreign_key :release_slice_id, :release_slices, type: :uuid

      String :title, null: false
      String :description, null: false, default: ''
      String :status, null: false, default: 'planned'

      Integer :position, null: false
      foreign_key :split_from_id, :stories, type: :uuid

      Integer :deploy_count, null: false, default: 0
      column :first_deployed_at, 'timestamptz'
      column :last_deployed_at, 'timestamptz'
      column :released_at, 'timestamptz'

      column :archived_at, 'timestamptz'
      foreign_key :created_by_id, :people, type: :uuid, null: false
      Integer :lock_version, null: false, default: 0
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      constraint(:valid_status) { Sequel.lit("status IN ('planned', 'active', 'released')") }
      constraint(:deploy_count_positive) { Sequel.lit("deploy_count >= 0") }
      constraint(:released_at_status_agree) do
        Sequel.lit("(released_at IS NULL AND status IN ('planned', 'active')) OR (released_at IS NOT NULL AND status = 'released')")
      end
      constraint(:deploy_fields_coherent) do
        Sequel.lit(<<~CHECK)
          (deploy_count = 0 AND first_deployed_at IS NULL AND last_deployed_at IS NULL)
          OR
          (deploy_count > 0 AND first_deployed_at IS NOT NULL AND last_deployed_at IS NOT NULL AND first_deployed_at <= last_deployed_at)
        CHECK
      end
    end

    run "ALTER TABLE stories ADD CONSTRAINT uq_stories_position UNIQUE (task_id, position) DEFERRABLE INITIALLY DEFERRED"

    # -- STORY ASSIGNMENTS ----------------------------

    create_table(:story_assignments) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :story_id, :stories, type: :uuid, null: false
      foreign_key :person_id, :people, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      column :assigned_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      unique [:story_id, :person_id]
    end

    run "CREATE UNIQUE INDEX idx_one_active_story_per_person ON story_assignments (person_id, team_id)"

    # -- STORY NOTES ----------------------------------

    create_table(:story_notes) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :story_id, :stories, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :note_kind, null: false
      String :body, null: false
      foreign_key :created_by_id, :people, type: :uuid, null: false
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      constraint(:valid_note_kind) { Sequel.lit("note_kind IN ('sizing', 'general')") }
      index [:story_id, :created_at], name: :idx_story_notes_story
    end

    # -- EVENTS (append-only) -------------------------

    run <<~SQL
      CREATE TABLE events (
          id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          event_no        bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
          team_id         uuid        NOT NULL REFERENCES teams (id),
          map_id          uuid        REFERENCES maps (id),
          actor_id        uuid        NOT NULL REFERENCES people (id),
          occurred_at     timestamptz NOT NULL DEFAULT now(),
          entity_type     text        NOT NULL,
          entity_id       uuid        NOT NULL,
          action          text        NOT NULL,
          before_state    jsonb       NOT NULL DEFAULT '{}',
          after_state     jsonb       NOT NULL DEFAULT '{}',
          correlation_id  uuid
      );
    SQL

    # Append-only trigger
    run <<~SQL
      CREATE OR REPLACE FUNCTION prevent_event_mutation()
      RETURNS TRIGGER AS $$
      BEGIN
          RAISE EXCEPTION 'events table is append-only: % not allowed', TG_OP;
          RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE TRIGGER enforce_append_only
          BEFORE UPDATE OR DELETE ON events
          FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();
    SQL

    # -- INDEXES --------------------------------------

    run "CREATE INDEX idx_activities_map ON activities (map_id, position) WHERE archived_at IS NULL"
    run "CREATE INDEX idx_tasks_activity ON tasks (activity_id, position) WHERE archived_at IS NULL"
    run "CREATE INDEX idx_stories_task ON stories (task_id, position) WHERE archived_at IS NULL"
    run "CREATE INDEX idx_slices_map ON release_slices (map_id, position) WHERE archived_at IS NULL"
    run "CREATE INDEX idx_stories_active ON stories (map_id) WHERE status = 'active' AND archived_at IS NULL"
    run "CREATE INDEX idx_events_entity ON events (entity_type, entity_id, occurred_at)"
    run "CREATE INDEX idx_events_map_action ON events (map_id, action, occurred_at) WHERE map_id IS NOT NULL"
    run "CREATE INDEX idx_events_actor ON events (actor_id, occurred_at)"
    run "CREATE INDEX idx_events_team ON events (team_id, occurred_at)"
    run "CREATE INDEX idx_events_deploys ON events (entity_id, occurred_at) WHERE entity_type = 'story' AND action = 'deployed'"
    run "CREATE INDEX idx_events_releases ON events (map_id, occurred_at) WHERE entity_type = 'story' AND action = 'released'"
    run "CREATE INDEX idx_events_assignments ON events (map_id, occurred_at) WHERE entity_type = 'story' AND action IN ('person_assigned', 'person_unassigned')"
    run "CREATE INDEX idx_stories_split_from ON stories (split_from_id) WHERE split_from_id IS NOT NULL"
    run "CREATE INDEX idx_events_correlation ON events (correlation_id) WHERE correlation_id IS NOT NULL"

    # -- ROW LEVEL SECURITY ---------------------------

    %w[maps activities tasks release_slices stories story_assignments
       story_notes team_constraints team_holidays events personas activity_personas].each do |tbl|
      run "ALTER TABLE #{tbl} ENABLE ROW LEVEL SECURITY"
      run "CREATE POLICY team_isolation ON #{tbl} USING (team_id = current_setting('app.current_team_id')::uuid)"
    end
  end

  down do
    # Drop in reverse dependency order
    %w[events story_notes story_assignments stories release_slices tasks
       activity_personas activities personas maps team_holidays team_constraints
       invitations team_memberships person_identities people teams].each do |tbl|
      run "DROP TABLE IF EXISTS #{tbl} CASCADE"
    end

    run "DROP FUNCTION IF EXISTS enforce_map_cap() CASCADE"
    run "DROP FUNCTION IF EXISTS prevent_event_mutation() CASCADE"
    run "DROP FUNCTION IF EXISTS enforce_min_one_persona() CASCADE"
    run "DROP FUNCTION IF EXISTS enforce_activity_has_persona() CASCADE"
  end
end
