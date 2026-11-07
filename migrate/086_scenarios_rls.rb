# frozen_string_literal: true

Sequel.migration do
  up do
    run 'ALTER TABLE scenarios ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE scenarios FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON scenarios
        USING (
          EXISTS (
            SELECT 1 FROM stories
            WHERE stories.id = scenarios.story_id
          )
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY IF EXISTS team_isolation ON scenarios'
    run 'ALTER TABLE scenarios NO FORCE ROW LEVEL SECURITY'
    run 'ALTER TABLE scenarios DISABLE ROW LEVEL SECURITY'
  end
end
