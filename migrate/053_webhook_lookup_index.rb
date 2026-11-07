# frozen_string_literal: true

Sequel.migration do
  up do
    add_index :monitored_repos, [:provider_installation_id, :provider_repo_id],
              name: :idx_monitored_repos_webhook_lookup
  end

  down do
    drop_index :monitored_repos, nil, name: :idx_monitored_repos_webhook_lookup
  end
end
