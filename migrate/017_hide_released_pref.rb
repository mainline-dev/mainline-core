# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :map_view_prefs, :hide_released, TrueClass, null: false, default: false
  end

  down do
    drop_column :map_view_prefs, :hide_released
  end
end
