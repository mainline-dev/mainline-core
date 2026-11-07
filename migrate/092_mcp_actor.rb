# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:teams) do
      add_foreign_key :mcp_actor_id, :actors, type: :uuid
    end
  end
end
