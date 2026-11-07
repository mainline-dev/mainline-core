# frozen_string_literal: true

Sequel.migration do
  RLS_TABLES = %w[
    maps activities tasks release_slices stories story_assignments
    team_constraints events personas activity_personas
  ].freeze

  up do
    password = ENV.fetch('MAINLINE_APP_USER_DATABASE_PASSWORD', 'app_password')

    run <<~SQL
      DO $$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mainline_app') THEN
          CREATE ROLE mainline_app LOGIN PASSWORD #{DB.literal(password)};
        END IF;
      END $$
    SQL

    run "GRANT USAGE ON SCHEMA public TO mainline_app"
    run "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mainline_app"
    run "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mainline_app"
    run "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO mainline_app"

    run "ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mainline_app"
    run "ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mainline_app"
    run "ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO mainline_app"

    RLS_TABLES.each do |tbl|
      run "DROP POLICY IF EXISTS team_isolation ON #{tbl}"
      run <<~SQL
        CREATE POLICY team_isolation ON #{tbl}
          USING (
            team_id = current_setting('app.current_team_id', true)::uuid
            OR current_setting('app.rls_bypass', true) = 'true'
          )
      SQL
    end

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

        DELETE FROM story_assignments WHERE team_id = p_team_id;
        DELETE FROM scenarios WHERE story_id IN (SELECT id FROM stories WHERE team_id = p_team_id);
        DELETE FROM stories WHERE team_id = p_team_id;
        DELETE FROM release_slices WHERE team_id = p_team_id;
        DELETE FROM tasks WHERE team_id = p_team_id;
        DELETE FROM activity_personas WHERE team_id = p_team_id;
        DELETE FROM activities WHERE team_id = p_team_id;
        DELETE FROM personas WHERE team_id = p_team_id;
        DELETE FROM map_view_prefs WHERE map_id IN (SELECT id FROM maps WHERE team_id = p_team_id);
        DELETE FROM maps WHERE team_id = p_team_id;
        DELETE FROM team_constraints WHERE team_id = p_team_id;
      END;
      $$
    SQL

    run "REVOKE ALL ON FUNCTION delete_team_data(uuid) FROM PUBLIC"
    run "GRANT EXECUTE ON FUNCTION delete_team_data(uuid) TO mainline_app"
  end

  down do
    RLS_TABLES.each do |tbl|
      run "DROP POLICY IF EXISTS team_isolation ON #{tbl}"
      run "CREATE POLICY team_isolation ON #{tbl} USING (team_id = current_setting('app.current_team_id')::uuid)"
    end

    run "DROP FUNCTION IF EXISTS delete_team_data(uuid)"

    run "ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public REVOKE ALL ON TABLES FROM mainline_app"
    run "ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public REVOKE ALL ON SEQUENCES FROM mainline_app"
    run "ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM mainline_app"
    run "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM mainline_app"
    run "REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM mainline_app"
    run "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM mainline_app"
    run "REVOKE USAGE ON SCHEMA public FROM mainline_app"
    run "DROP ROLE IF EXISTS mainline_app"
  end
end
