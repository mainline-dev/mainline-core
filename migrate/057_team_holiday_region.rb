# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :holiday_region, String, null: true
    end
  end
end
