# frozen_string_literal: true

Sequel.migration do
  up do
    run "ALTER TABLE stories DROP CONSTRAINT uq_stories_position"
    run "CREATE UNIQUE INDEX uq_stories_position ON stories(task_id, position) WHERE archived_at IS NULL"
  end

  down do
    run "DROP INDEX uq_stories_position"
    run "ALTER TABLE stories ADD CONSTRAINT uq_stories_position UNIQUE (task_id, position) DEFERRABLE INITIALLY DEFERRED"
  end
end
