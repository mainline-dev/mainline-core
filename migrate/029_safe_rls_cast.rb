# frozen_string_literal: true

Sequel.migration do
  RLS_TABLES = %w[maps activities tasks release_slices stories story_assignments team_constraints events personas activity_personas].freeze

  up do
    RLS_TABLES.each do |tbl|
      run "DROP POLICY IF EXISTS team_isolation ON #{tbl}"
      run <<~SQL
        CREATE POLICY team_isolation ON #{tbl}
          USING (
            team_id::text = current_setting('app.current_team_id', true)
            OR current_setting('app.rls_bypass', true) = 'true'
          )
      SQL
    end
  end

  down do
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
  end
end
