# frozen_string_literal: true

Sequel.migration do
  RLS_TABLES = %w[
    maps activities tasks release_slices stories story_assignments
    team_constraints events personas activity_personas
  ].freeze

  up do
    RLS_TABLES.each do |tbl|
      run "ALTER TABLE #{tbl} FORCE ROW LEVEL SECURITY"
    end
  end

  down do
    RLS_TABLES.each do |tbl|
      run "ALTER TABLE #{tbl} NO FORCE ROW LEVEL SECURITY"
    end
  end
end
