# frozen_string_literal: true

Sequel.migration do
  up do
    run "ALTER TABLE tasks DROP CONSTRAINT uq_tasks_position"
    run "CREATE UNIQUE INDEX uq_tasks_position ON tasks(activity_id, position) WHERE archived_at IS NULL"
  end

  down do
    run "DROP INDEX uq_tasks_position"
    run "ALTER TABLE tasks ADD CONSTRAINT uq_tasks_position UNIQUE (activity_id, position) DEFERRABLE INITIALLY DEFERRED"
  end
end
