# frozen_string_literal: true

# The Ticket Museum: issues imported from another tool (Jira first), frozen
# and read-only until someone pulls one onto the map. One row per issue per
# team, matched on the source's key when a newer export is imported. Isolated
# by team and removed with the team's data, before the stories they point at.
Sequel.migration do
  up do
    create_table(:museum_items) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :source_key, size: 50, null: false
      String :issue_type, size: 50, null: false
      String :summary, size: 255, null: false
      String :description, text: true, null: false, default: ''
      TrueClass :in_progress, null: false, default: false
      String :parent_key, size: 50
      column :labels, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      column :comments, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      column :links, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      column :source_created_at, 'timestamptz'
      foreign_key :story_id, :stories, type: :uuid
      column :pulled_at, 'timestamptz'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index %i[team_id source_key], unique: true
      index %i[team_id story_id]
      index %i[team_id parent_key]

      constraint(:pulled_fields_together) do
        Sequel.lit('(story_id IS NULL AND pulled_at IS NULL) OR (story_id IS NOT NULL AND pulled_at IS NOT NULL)')
      end
    end

    run 'GRANT SELECT, INSERT, UPDATE, DELETE ON museum_items TO mainline_app'
    run 'ALTER TABLE museum_items ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE museum_items FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON museum_items
        USING (
          (team_id)::text = current_setting('app.current_team_id', true)
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

        DELETE FROM museum_items WHERE team_id = p_team_id;
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

    drop_table(:museum_items)
  end
end
