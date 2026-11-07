# frozen_string_literal: true

Sequel.migration do
  up do
    run 'DROP POLICY team_isolation ON team_installations'
    run <<~SQL
      CREATE POLICY team_isolation ON team_installations
        USING (
          team_id::text = current_setting('app.current_team_id', true)
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY team_isolation ON team_installations'
    run <<~SQL
      CREATE POLICY team_isolation ON team_installations
        USING (
          team_id = current_setting('app.current_team_id')::uuid
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end
end
