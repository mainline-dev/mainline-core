# frozen_string_literal: true

Sequel.migration do
  up do
    unless schema(:tracked_branches).any? { |col, _| col == :merged_at }
      alter_table(:tracked_branches) do
        add_column :merged_at, :timestamptz
      end
    end
  end

  down do
    alter_table(:tracked_branches) do
      drop_column :merged_at
    end
  end
end
