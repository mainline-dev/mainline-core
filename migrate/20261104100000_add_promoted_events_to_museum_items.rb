# frozen_string_literal: true

# How many events the story had when an exhibit was promoted to it, so sending
# the exhibit back can tell whether anything has happened to the story since.
Sequel.migration do
  up do
    alter_table(:museum_items) do
      add_column :promoted_events, Integer
    end
  end

  down do
    alter_table(:museum_items) do
      drop_column :promoted_events
    end
  end
end
