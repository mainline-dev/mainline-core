# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE actors (
        id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        kind text NOT NULL DEFAULT 'person',
        name text NOT NULL,
        CONSTRAINT valid_kind CHECK (kind IN ('person', 'system'))
      )
    SQL

    run <<~SQL
      INSERT INTO actors (id, kind, name)
      SELECT id, 'person', name FROM people
    SQL

    alter_table(:people) do
      add_foreign_key :actor_id, :actors, type: :uuid
    end

    run "UPDATE people SET actor_id = id"

    alter_table(:people) do
      set_column_not_null :actor_id
    end

    run "ALTER TABLE events DROP CONSTRAINT events_actor_id_fkey"
    run "ALTER TABLE events ADD CONSTRAINT events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES actors (id)"
  end

  down do
    run "ALTER TABLE events DROP CONSTRAINT events_actor_id_fkey"
    run "ALTER TABLE events DISABLE TRIGGER enforce_append_only"
    run "DELETE FROM events WHERE actor_id NOT IN (SELECT id FROM people)"
    run "ALTER TABLE events ENABLE TRIGGER enforce_append_only"
    run "ALTER TABLE events ADD CONSTRAINT events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES people (id)"

    alter_table(:people) do
      drop_column :actor_id
    end

    drop_table(:actors)
  end
end
