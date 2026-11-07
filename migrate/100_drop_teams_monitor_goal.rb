# frozen_string_literal: true

# The CI Monitor's dashboard window became a fixed constant in the plugin;
# nothing reads or writes this column any more.
Sequel.migration do
  up do
    alter_table(:teams) do
      drop_column :monitor_goal
    end
  end

  down do
    alter_table(:teams) do
      add_column :monitor_goal, Integer, null: false, default: 72
    end
  end
end
