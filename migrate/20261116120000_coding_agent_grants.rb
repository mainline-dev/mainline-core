# frozen_string_literal: true

# What a person gives a coding agent: a grant to read the maps of the teams
# they ticked, held as a personal token they made or, later, as an OAuth
# sign-in from a client. A grant belongs to its person, like their sign-in
# identities, and goes with them. The teams it covers are team rows, isolated
# by team and removed with the team's data. Tokens are kept only as SHA-256
# digests, looked up by digest.
Sequel.migration do
  up do
    create_table(:oauth_grants) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :person_id, :people, type: :uuid, null: false, on_delete: :cascade
      String :client_id, size: 2048
      String :name, size: 100
      String :scope, size: 100, null: false
      String :resource, size: 2048, null: false
      column :expires_at, 'timestamptz'
      column :last_used_at, 'timestamptz'
      column :revoked_at, 'timestamptz'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index :person_id
    end

    create_table(:oauth_grant_teams) do
      foreign_key :grant_id, :oauth_grants, type: :uuid, null: false, on_delete: :cascade
      foreign_key :team_id, :teams, type: :uuid, null: false
      primary_key %i[grant_id team_id]

      index :team_id
    end

    create_table(:oauth_access_tokens) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :grant_id, :oauth_grants, type: :uuid, null: false, on_delete: :cascade
      String :token_hash, size: 64, null: false, unique: true
      column :expires_at, 'timestamptz', null: false
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index :grant_id
    end

    run 'GRANT SELECT, INSERT, UPDATE, DELETE ON oauth_grants, oauth_grant_teams, oauth_access_tokens TO mainline_app'
    run 'ALTER TABLE oauth_grant_teams ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE oauth_grant_teams FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON oauth_grant_teams
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

        DELETE FROM oauth_grant_teams WHERE team_id = p_team_id;
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

    drop_table(:oauth_access_tokens)
    drop_table(:oauth_grant_teams)
    drop_table(:oauth_grants)
  end
end
