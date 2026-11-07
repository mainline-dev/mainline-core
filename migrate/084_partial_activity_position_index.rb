# frozen_string_literal: true

Sequel.migration do
  up do
    run "ALTER TABLE activities DROP CONSTRAINT uq_activities_position"
    run "CREATE UNIQUE INDEX uq_activities_position ON activities(map_id, position) WHERE archived_at IS NULL"
  end

  down do
    run "DROP INDEX uq_activities_position"
    run "ALTER TABLE activities ADD CONSTRAINT uq_activities_position UNIQUE (map_id, position) DEFERRABLE INITIALLY DEFERRED"
  end
end
