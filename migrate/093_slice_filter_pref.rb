# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:map_view_prefs) do
      add_foreign_key :slice_filter_id, :release_slices, type: :uuid, on_delete: :set_null
    end
  end

  down do
    alter_table(:map_view_prefs) do
      drop_column :slice_filter_id
    end
  end
end
