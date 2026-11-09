# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:scenarios) do
      add_column :name, String, size: 80, null: true
    end
  end
end
