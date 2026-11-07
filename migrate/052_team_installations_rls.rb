# frozen_string_literal: true

Sequel.migration do
  up do
    run 'GRANT SELECT, INSERT, UPDATE, DELETE ON team_installations TO mainline_app'
    run 'ALTER TABLE team_installations ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE team_installations FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON team_installations
        USING (
          team_id = current_setting('app.current_team_id')::uuid
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY team_isolation ON team_installations'
    run 'ALTER TABLE team_installations DISABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE team_installations NO FORCE ROW LEVEL SECURITY'
    run 'REVOKE SELECT, INSERT, UPDATE, DELETE ON team_installations FROM mainline_app'
  end
end
