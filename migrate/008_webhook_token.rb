# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:teams) do
      add_column :webhook_token, String
      add_foreign_key :webhook_actor_id, :actors, type: :uuid
    end
  end
end
