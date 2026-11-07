# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :cert_token, String, size: 24, null: true
      add_column :cert_public, TrueClass, default: false
      add_index :cert_token, unique: true, where: Sequel.~(cert_token: nil)
    end
  end
end
