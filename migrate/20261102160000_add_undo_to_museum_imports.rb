# frozen_string_literal: true

# What an import changed, so the most recent import can be undone: each key
# it added (with no earlier state) and each item it refreshed, as it was.
Sequel.migration do
  up do
    alter_table(:museum_imports) do
      add_column :previous, :jsonb
      add_column :undone_at, 'timestamptz'
    end
  end

  down do
    alter_table(:museum_imports) do
      drop_column :undone_at
      drop_column :previous
    end
  end
end
