# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:museum_imports) do
      add_column :backbone, :jsonb
    end
  end
end
