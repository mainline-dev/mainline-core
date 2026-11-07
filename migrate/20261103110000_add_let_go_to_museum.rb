# frozen_string_literal: true

# Letting go of exhibits. The curator's rules mark each exhibit worth letting
# go with the group that caught it (and a duplicate with its twin); a person
# reviews them and sends the ones they agree with to storage, with a note
# saying why. Kept exhibits are never suggested again; "Not now" snoozes the
# prompt for the team. Duplicates are found by trigram similarity of summaries.
Sequel.migration do
  up do
    run 'CREATE EXTENSION IF NOT EXISTS pg_trgm'

    alter_table(:museum_items) do
      add_column :storage_note, String, size: 255
      add_column :kept_at, 'timestamptz'
      add_column :let_go_group, String, size: 20
      add_column :let_go_pair_key, String, size: 50
      add_constraint(:let_go_groups, Sequel.lit("let_go_group IN ('stale', 'dupes', 'repro', 'vague', 'covered')"))
      add_index %i[team_id let_go_group], where: Sequel.lit('let_go_group IS NOT NULL')
    end
    run 'CREATE INDEX museum_items_summary_trgm ON museum_items USING gin (lower(summary) gin_trgm_ops)'

    alter_table(:teams) do
      add_column :let_go_snoozed_until, 'timestamptz'
    end
  end

  down do
    alter_table(:teams) do
      drop_column :let_go_snoozed_until
    end

    run 'DROP INDEX museum_items_summary_trgm'
    alter_table(:museum_items) do
      drop_index %i[team_id let_go_group]
      drop_constraint(:let_go_groups)
      drop_column :let_go_pair_key
      drop_column :let_go_group
      drop_column :kept_at
      drop_column :storage_note
    end
    run 'DROP EXTENSION IF EXISTS pg_trgm'
  end
end
