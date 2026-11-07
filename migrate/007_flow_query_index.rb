# frozen_string_literal: true

Sequel.migration do
  change do
    add_index :events, [:team_id, :entity_type, :action, :occurred_at],
              name: :idx_events_team_entity_action
  end
end
