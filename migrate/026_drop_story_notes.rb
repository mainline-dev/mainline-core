# frozen_string_literal: true

Sequel.migration do
  up do
    drop_table(:story_notes)
  end

  down do
    create_table(:story_notes) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :story_id, :stories, type: :uuid, null: false
      foreign_key :team_id, :teams, type: :uuid, null: false
      String :note_kind, null: false
      String :body, null: false
      foreign_key :created_by_id, :people, type: :uuid, null: false
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      constraint(:valid_note_kind) { Sequel.lit("note_kind IN ('sizing', 'general')") }
      index [:story_id, :created_at], name: :idx_story_notes_story
    end
  end
end
