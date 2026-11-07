# frozen_string_literal: true

Sequel.migration do
  up do
    run 'ALTER TABLE map_view_prefs ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE map_view_prefs FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON map_view_prefs
        USING (
          EXISTS (
            SELECT 1 FROM maps
            WHERE maps.id = map_view_prefs.map_id
          )
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    run 'DROP POLICY IF EXISTS team_isolation ON map_view_prefs'
    run 'ALTER TABLE map_view_prefs NO FORCE ROW LEVEL SECURITY'
    run 'ALTER TABLE map_view_prefs DISABLE ROW LEVEL SECURITY'
  end
end
