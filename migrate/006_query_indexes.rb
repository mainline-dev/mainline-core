# frozen_string_literal: true

Sequel.migration do
  change do
    add_index :stories, [:team_id, :status]

    add_index :events, [:entity_type, :entity_id, :action, :event_no], name: :idx_events_entity_action

    add_index :tasks, :map_id, where: { archived_at: nil }, name: :idx_tasks_map_id_active

    add_index :story_assignments, :team_id
  end
end
