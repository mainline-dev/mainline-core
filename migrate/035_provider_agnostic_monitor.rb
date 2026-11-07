# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:monitored_repos) do
      drop_constraint(:monitored_repos_team_id_github_repo_id_key)
      rename_column :github_installation_id, :provider_installation_id
      rename_column :github_repo_id, :provider_repo_id
      add_column :provider, String, null: false, default: 'github'
      add_unique_constraint [:team_id, :provider, :provider_repo_id]
    end

    alter_table(:teams) do
      rename_column :github_installation_id, :provider_installation_id
    end
  end

  down do
    alter_table(:teams) do
      rename_column :provider_installation_id, :github_installation_id
    end

    alter_table(:monitored_repos) do
      drop_constraint(:monitored_repos_team_id_provider_provider_repo_id_key)
      drop_column :provider
      rename_column :provider_installation_id, :github_installation_id
      rename_column :provider_repo_id, :github_repo_id
      add_unique_constraint [:team_id, :github_repo_id]
    end
  end
end
