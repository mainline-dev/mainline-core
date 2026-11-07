# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :monitored_repos, :backfill_status, String, default: 'complete'
  end

  down do
    drop_column :monitored_repos, :backfill_status
  end
end
