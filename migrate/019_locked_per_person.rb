# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :map_view_prefs, :locked, TrueClass, null: false, default: false
    drop_column :maps, :locked
  end

  down do
    add_column :maps, :locked, TrueClass, null: false, default: false
    drop_column :map_view_prefs, :locked
  end
end
