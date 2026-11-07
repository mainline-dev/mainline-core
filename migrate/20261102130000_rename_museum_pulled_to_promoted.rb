# frozen_string_literal: true

# Taking an item out of the Ticket Museum is called promoting it ("pull"
# clashed with pull requests).
Sequel.migration do
  up do
    alter_table(:museum_items) do
      rename_column :pulled_at, :promoted_at
    end
    run 'ALTER TABLE museum_items RENAME CONSTRAINT pulled_fields_together TO promoted_fields_together'
  end

  down do
    run 'ALTER TABLE museum_items RENAME CONSTRAINT promoted_fields_together TO pulled_fields_together'
    alter_table(:museum_items) do
      rename_column :promoted_at, :pulled_at
    end
  end
end
