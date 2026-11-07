# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:map_view_prefs) do
      foreign_key :person_id, :people, type: :uuid, null: false, on_delete: :cascade
      foreign_key :map_id,    :maps,   type: :uuid, null: false, on_delete: :cascade
      TrueClass :active, null: false, default: false
      TrueClass :slices, null: false, default: false

      primary_key [:person_id, :map_id]
    end
  end

  down do
    drop_table(:map_view_prefs)
  end
end
