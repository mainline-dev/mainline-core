# frozen_string_literal: true

# Events core sends to services. Each is written in the same transaction as
# the change it describes, and outlives the team it names, so there is no
# foreign key to teams.
Sequel.migration do
  change do
    create_table(:outbox_events) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      column :event_type, String, size: 100, null: false
      column :payload, :jsonb, null: false
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run 'GRANT SELECT, INSERT ON outbox_events TO mainline_app'
  end
end
