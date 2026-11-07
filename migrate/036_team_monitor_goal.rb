# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:teams) do
      add_column :monitor_goal, Integer, null: false, default: 72
    end
    alter_table(:monitored_repos) do
      set_column_default :threshold_hours, 72
    end
  end

  down do
    alter_table(:monitored_repos) do
      set_column_default :threshold_hours, 24
    end
    alter_table(:teams) do
      drop_column :monitor_goal
    end
  end
end
