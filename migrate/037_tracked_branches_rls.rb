# frozen_string_literal: true

Sequel.migration do
  up do
    run 'ALTER TABLE tracked_branches ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE tracked_branches FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON tracked_branches
        USING (
          EXISTS (
            SELECT 1 FROM monitored_repos
            WHERE monitored_repos.id = tracked_branches.monitored_repo_id
          )
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY IF EXISTS team_isolation ON tracked_branches'
    run 'ALTER TABLE tracked_branches NO FORCE ROW LEVEL SECURITY'
    run 'ALTER TABLE tracked_branches DISABLE ROW LEVEL SECURITY'
  end
end
