# frozen_string_literal: true

Sequel.migration do
  up do
    run 'ALTER TABLE invitations ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE invitations FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON invitations
        USING (
          (team_id)::text = current_setting('app.current_team_id', true)
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY team_isolation ON invitations'
    run 'ALTER TABLE invitations NO FORCE ROW LEVEL SECURITY'
    run 'ALTER TABLE invitations DISABLE ROW LEVEL SECURITY'
  end
end
