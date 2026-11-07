# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:story_notes) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :story_id, :stories, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :note_type, null: false
      column :dismissed_at, 'timestamptz'
      foreign_key :dismissed_by, :people, type: :uuid
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      constraint(:valid_note_type) do
        Sequel.lit("note_type IN ('split_candidate', 'stale_story', 'stale_solo', 'stale_flag')")
      end
      constraint(:dismiss_fields_together) do
        Sequel.lit('(dismissed_at IS NULL AND dismissed_by IS NULL) OR (dismissed_at IS NOT NULL AND dismissed_by IS NOT NULL)')
      end
    end

    run <<~SQL
      CREATE UNIQUE INDEX idx_one_active_note_per_type
        ON story_notes (story_id, note_type)
        WHERE dismissed_at IS NULL
    SQL

    run 'GRANT SELECT, INSERT, UPDATE ON story_notes TO mainline_app'
    run 'ALTER TABLE story_notes ENABLE ROW LEVEL SECURITY'
    run 'ALTER TABLE story_notes FORCE ROW LEVEL SECURITY'
    run <<~SQL
      CREATE POLICY team_isolation ON story_notes
        USING (
          team_id = current_setting('app.current_team_id')::uuid
          OR current_setting('app.rls_bypass', true) = 'true'
        )
    SQL
  end

  down do
    drop_table(:story_notes)
  end
end
