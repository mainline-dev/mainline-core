# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :github_installation_id, :bigint
    end
  end
end
