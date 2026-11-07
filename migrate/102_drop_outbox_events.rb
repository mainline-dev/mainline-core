# frozen_string_literal: true

# The outbox was for separate services, a design dropped before it shipped.
Sequel.migration do
  up do
    drop_table(:outbox_events)
  end

  down do
    create_table(:outbox_events) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      column :event_type, String, size: 100, null: false
      column :payload, :jsonb, null: false
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')
    end

    run 'GRANT SELECT, INSERT ON outbox_events TO mainline_app'
  end
end
