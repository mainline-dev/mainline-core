# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:map_view_prefs) do
      add_index :slice_filter_id
    end
  end

  down do
    alter_table(:map_view_prefs) do
      drop_index :slice_filter_id
    end
  end
end
