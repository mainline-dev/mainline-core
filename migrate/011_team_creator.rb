# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :creator_id, :uuid
    alter_table(:teams) do
      add_foreign_key [:creator_id], :people, name: :teams_creator_id_fkey
    end
  end

  down do
    alter_table(:teams) do
      drop_constraint :teams_creator_id_fkey
    end
    drop_column :teams, :creator_id
  end
end
