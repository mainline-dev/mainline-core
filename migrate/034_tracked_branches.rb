# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:monitored_repos) do
      add_column :last_push_at, 'timestamptz'
    end

    create_table(:tracked_branches) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :monitored_repo_id, :monitored_repos, type: :uuid, null: false
      column :branch_name_ciphertext, :text, null: false
      String :branch_name_bidx, null: false
      String :head_sha
      String :status, null: false, default: 'open'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :merged_at, 'timestamptz'
      column :abandoned_at, 'timestamptz'
      index :branch_name_bidx
      index :monitored_repo_id
    end

    run "DROP POLICY IF EXISTS team_isolation ON monitored_repos"
    run <<~SQL
      CREATE POLICY team_isolation ON monitored_repos
        USING (
          team_id::text = current_setting('app.current_team_id', true)
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    drop_table(:tracked_branches)
    alter_table(:monitored_repos) { drop_column :last_push_at }
  end
end
