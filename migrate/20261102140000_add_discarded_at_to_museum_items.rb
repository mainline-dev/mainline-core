# frozen_string_literal: true

# A museum item someone has set aside. It stays as a row, not deleted, so a
# later import of the same key does not bring it back; it can be restored.
Sequel.migration do
  up do
    alter_table(:museum_items) do
      add_column :discarded_at, 'timestamptz'
      add_constraint(:not_promoted_and_discarded, Sequel.lit('promoted_at IS NULL OR discarded_at IS NULL'))
    end
  end

  down do
    alter_table(:museum_items) do
      drop_constraint(:not_promoted_and_discarded)
      drop_column :discarded_at
    end
  end
end
