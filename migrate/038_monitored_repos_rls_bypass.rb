# frozen_string_literal: true

Sequel.migration do
  up do
    run 'DROP POLICY IF EXISTS team_isolation ON monitored_repos'
    run <<~SQL
      CREATE POLICY team_isolation ON monitored_repos
        USING (
          team_id::text = current_setting('app.current_team_id', true)
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY IF EXISTS team_isolation ON monitored_repos'
    run <<~SQL
      CREATE POLICY team_isolation ON monitored_repos
        USING (team_id = current_setting('app.current_team_id')::uuid)
    SQL
  end
end
