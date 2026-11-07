# frozen_string_literal: true

# When Jira last changed the issue, as the export says. Tells a ticket nobody
# has touched in a year from one that is still moving.
Sequel.migration do
  up do
    alter_table(:museum_items) do
      add_column :source_updated_at, 'timestamptz'
    end
  end

  down do
    alter_table(:museum_items) do
      drop_column :source_updated_at
    end
  end
end
