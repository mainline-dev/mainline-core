# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :heatmap_mode, String, null: false, default: 'average'
    end
  end
end
