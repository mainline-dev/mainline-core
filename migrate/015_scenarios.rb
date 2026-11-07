# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:scenarios) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :story_id, :stories, type: :uuid, null: false

      String :given_text, size: 100, null: false
      String :when_text, size: 100, null: false
      String :then_text, size: 100, null: false

      Integer :position, null: false

      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
      column :updated_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index :story_id
    end
  end
end
