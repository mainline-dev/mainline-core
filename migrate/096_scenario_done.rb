# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:scenarios) do
      add_column :done_at, 'timestamptz'
    end
  end
end
