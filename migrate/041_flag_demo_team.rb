# frozen_string_literal: true

Sequel.migration do
  up do
    add_index :teams, :id, unique: true, where: { system_team: true }, name: :teams_one_system_team

    from(:teams).where(name: 'Clearview Analytics', system_team: false).update(system_team: true)
  end

  down do
    from(:teams).where(name: 'Clearview Analytics', system_team: true).update(system_team: false)

    drop_index :teams, :id, name: :teams_one_system_team
  end
end
