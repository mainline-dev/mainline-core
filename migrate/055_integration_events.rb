# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:integration_events) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :monitored_repo_id, :monitored_repos, type: :uuid, null: false
      column :event_type, String, null: false
      column :occurred_at, 'timestamptz', null: false
      foreign_key :tracked_branch_id, :tracked_branches, type: :uuid, null: true
      column :created_at, 'timestamptz', default: Sequel.lit('now()')
      index [:monitored_repo_id, :occurred_at]
    end

    run 'GRANT SELECT, INSERT, DELETE ON integration_events TO mainline_app'
    run 'ALTER TABLE integration_events ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE integration_events FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON integration_events
        USING (
          monitored_repo_id IN (
            SELECT id FROM monitored_repos
            WHERE team_id::text = current_setting('app.current_team_id', true)
          )
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL

    run <<~SQL
      CREATE OR REPLACE FUNCTION delete_team_data(p_team_id uuid)
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public
      AS $$
      BEGIN
        ALTER TABLE events DISABLE TRIGGER enforce_append_only;
        DELETE FROM events WHERE team_id = p_team_id;
        ALTER TABLE events ENABLE TRIGGER enforce_append_only;

        DELETE FROM integration_events WHERE monitored_repo_id IN
          (SELECT id FROM monitored_repos WHERE team_id = p_team_id);
        DELETE FROM tracked_branches WHERE monitored_repo_id IN
          (SELECT id FROM monitored_repos WHERE team_id = p_team_id);
        DELETE FROM monitored_repos WHERE team_id = p_team_id;

        DELETE FROM story_notes WHERE team_id = p_team_id;
        DELETE FROM story_assignments WHERE team_id = p_team_id;
        DELETE FROM scenarios WHERE story_id IN (SELECT id FROM stories WHERE team_id = p_team_id);
        DELETE FROM stories WHERE team_id = p_team_id;
        DELETE FROM release_slices WHERE team_id = p_team_id;
        DELETE FROM tasks WHERE team_id = p_team_id;

        ALTER TABLE activity_personas DISABLE TRIGGER check_min_one_persona;
        DELETE FROM activity_personas WHERE team_id = p_team_id;
        DELETE FROM activities WHERE team_id = p_team_id;
        ALTER TABLE activity_personas ENABLE TRIGGER check_min_one_persona;

        DELETE FROM personas WHERE team_id = p_team_id;
        DELETE FROM map_view_prefs WHERE map_id IN (SELECT id FROM maps WHERE team_id = p_team_id);
        DELETE FROM maps WHERE team_id = p_team_id;
        DELETE FROM team_constraints WHERE team_id = p_team_id;
      END;
      $$
    SQL
  end

  down do
    run 'DROP POLICY team_isolation ON integration_events'
    run 'ALTER TABLE integration_events DISABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE integration_events NO FORCE ROW LEVEL SECURITY'
    run 'REVOKE SELECT, INSERT, DELETE ON integration_events FROM mainline_app'
    drop_table(:integration_events)

    run <<~SQL
      CREATE OR REPLACE FUNCTION delete_team_data(p_team_id uuid)
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public
      AS $$
      BEGIN
        ALTER TABLE events DISABLE TRIGGER enforce_append_only;
        DELETE FROM events WHERE team_id = p_team_id;
        ALTER TABLE events ENABLE TRIGGER enforce_append_only;

        DELETE FROM tracked_branches WHERE monitored_repo_id IN
          (SELECT id FROM monitored_repos WHERE team_id = p_team_id);
        DELETE FROM monitored_repos WHERE team_id = p_team_id;

        DELETE FROM story_notes WHERE team_id = p_team_id;
        DELETE FROM story_assignments WHERE team_id = p_team_id;
        DELETE FROM scenarios WHERE story_id IN (SELECT id FROM stories WHERE team_id = p_team_id);
        DELETE FROM stories WHERE team_id = p_team_id;
        DELETE FROM release_slices WHERE team_id = p_team_id;
        DELETE FROM tasks WHERE team_id = p_team_id;

        ALTER TABLE activity_personas DISABLE TRIGGER check_min_one_persona;
        DELETE FROM activity_personas WHERE team_id = p_team_id;
        DELETE FROM activities WHERE team_id = p_team_id;
        ALTER TABLE activity_personas ENABLE TRIGGER check_min_one_persona;

        DELETE FROM personas WHERE team_id = p_team_id;
        DELETE FROM map_view_prefs WHERE map_id IN (SELECT id FROM maps WHERE team_id = p_team_id);
        DELETE FROM maps WHERE team_id = p_team_id;
        DELETE FROM team_constraints WHERE team_id = p_team_id;
      END;
      $$
    SQL
  end
end
