# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:monitored_repos) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :team_id, :teams, type: :uuid, null: false
      column :github_installation_id, :bigint, null: false
      column :github_repo_id, :bigint, null: false
      column :repo_name_ciphertext, :text, null: false
      String :repo_name_bidx, null: false
      String :default_branch, null: false, default: 'main'
      Integer :threshold_hours, null: false, default: 24
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      unique [:team_id, :github_repo_id]
      index :repo_name_bidx
    end
    run <<~SQL
      ALTER TABLE monitored_repos ENABLE ROW LEVEL SECURITY;
      ALTER TABLE monitored_repos FORCE ROW LEVEL SECURITY;
      CREATE POLICY team_isolation ON monitored_repos
        USING (team_id = current_setting('app.current_team_id')::uuid);
    SQL
  end
  down do
    drop_table(:monitored_repos)
  end
end
