# frozen_string_literal: true

# A push event remembers the commit it pushed, so the same delivery handled
# twice (a redelivery from the GitHub App's settings) counts once. Events from
# before this have no commit and are left as they are.
Sequel.migration do
  up do
    alter_table(:integration_events) do
      add_column :commit_sha, String, null: true
    end
    run <<~SQL
      CREATE UNIQUE INDEX idx_integration_events_one_push_per_commit
        ON integration_events (monitored_repo_id, commit_sha)
        WHERE event_type = 'push' AND commit_sha IS NOT NULL
    SQL
  end

  down do
    run 'DROP INDEX idx_integration_events_one_push_per_commit'
    alter_table(:integration_events) do
      drop_column :commit_sha
    end
  end
end
