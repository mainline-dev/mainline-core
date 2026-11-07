# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:tracked_branches) do
      drop_foreign_key [:monitored_repo_id]
      add_foreign_key [:monitored_repo_id], :monitored_repos, on_delete: :cascade
    end
  end

  down do
    alter_table(:tracked_branches) do
      drop_foreign_key [:monitored_repo_id]
      add_foreign_key [:monitored_repo_id], :monitored_repos
    end
  end
end
