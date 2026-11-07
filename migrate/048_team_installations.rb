# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:team_installations) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      column :provider, String, null: false, default: 'github'
      column :installation_id, :bigint, null: false
      column :org_name, String
      column :created_at, :timestamptz, default: Sequel.lit('now()')
      unique [:team_id, :provider, :installation_id]
    end

    from(:teams).where(Sequel.lit('provider_installation_id IS NOT NULL')).each do |team|
      from(:team_installations).insert(
        team_id: team[:id],
        provider: 'github',
        installation_id: team[:provider_installation_id]
      )
    end

    alter_table(:teams) do
      drop_column :provider_installation_id
    end
  end

  down do
    alter_table(:teams) do
      add_column :provider_installation_id, :bigint
    end

    from(:team_installations).each do |ti|
      from(:teams).where(id: ti[:team_id]).update(
        provider_installation_id: ti[:installation_id]
      )
    end

    drop_table(:team_installations)
  end
end
