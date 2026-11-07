# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :system_team, :boolean, default: false, null: false
  end

  down do
    drop_column :teams, :system_team
  end
end
