# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:tracked_branches) do
      add_column :merged_from_spike, :boolean, null: false, default: false
    end
  end
end
