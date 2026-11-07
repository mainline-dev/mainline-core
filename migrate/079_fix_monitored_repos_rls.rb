# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      DROP POLICY team_isolation ON monitored_repos;
      CREATE POLICY team_isolation ON monitored_repos
        USING (
          (team_id)::text = current_setting('app.current_team_id', true)
          OR current_setting('app.rls_bypass', true) = 'true'
        );
    SQL
  end

  down do
    run <<~SQL
      DROP POLICY team_isolation ON monitored_repos;
      CREATE POLICY team_isolation ON monitored_repos
        USING (
          (team_id)::text = current_setting('app.current_team_id', true)
          OR current_setting('app.rls_bypass', true) = 'true'
        );
    SQL
  end
end
