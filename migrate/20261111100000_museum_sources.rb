# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:museum_items) do
      add_column :source, String, size: 20, null: false, default: 'jira'
      add_column :origin, String, size: 255
      add_column :suggested, :jsonb
    end
    alter_table(:museum_imports) do
      add_column :source, String, size: 20, null: false, default: 'jira'
    end
  end
end
