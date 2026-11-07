# frozen_string_literal: true

# One upload of a Jira CSV to the Ticket Museum. An upload is staged first:
# the readable items wait in `items` and the rows that could not be read wait
# in `problems`, with the file's header, until someone imports or cancels it.
# Importing records what it did. Isolated by team and removed with the team's
# data; who imported is an actor, which outlives a deleted person.
Sequel.migration do
  up do
    create_table(:museum_imports) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      foreign_key :actor_id, :actors, type: :uuid, null: false
      String :file_name, size: 255, null: false
      String :status, size: 20, null: false
      column :header, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      column :items, :jsonb
      column :problems, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      Integer :finished, null: false, default: 0
      Integer :skipped, null: false, default: 0
      Integer :added, null: false, default: 0
      Integer :updated, null: false, default: 0
      Integer :promoted, null: false, default: 0
      Integer :discarded, null: false, default: 0
      column :imported_at, 'timestamptz'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index %i[team_id created_at]

      constraint(:museum_import_status, Sequel.lit("status IN ('staged', 'imported', 'cancelled', 'undone')"))
    end

    run 'GRANT SELECT, INSERT, UPDATE, DELETE ON museum_imports TO mainline_app'
    run 'ALTER TABLE museum_imports ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE museum_imports FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON museum_imports
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

        DELETE FROM museum_imports WHERE team_id = p_team_id;
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

    drop_table(:museum_imports)
  end
end
