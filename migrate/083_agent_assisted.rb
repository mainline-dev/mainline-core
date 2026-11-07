# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:stories) do
      add_column :agent_assisted, :boolean, null: false, default: false
    end
  end

  down do
    alter_table(:stories) do
      drop_column :agent_assisted
    end
  end
end
