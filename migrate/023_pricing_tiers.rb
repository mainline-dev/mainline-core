# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :person_cap, Integer, null: false, default: 16

    from(:teams).where(billing_state: 'solo').update(
      billing_state: 'active',
      person_cap: 8
    )

    alter_table(:teams) do
      set_column_default :billing_state, 'trialing'
    end

    run <<~SQL
      DROP TRIGGER IF EXISTS check_map_cap ON maps;
      DROP FUNCTION IF EXISTS enforce_map_cap();
    SQL
  end

  down do
    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_map_cap()
      RETURNS TRIGGER AS $$
      DECLARE
          active_count integer;
          cap integer;
          state text;
      BEGIN
          SELECT COUNT(*) INTO active_count
          FROM maps
          WHERE team_id = NEW.team_id
            AND archived_at IS NULL;

          SELECT billing_state INTO state
          FROM teams
          WHERE id = NEW.team_id;

          IF state IN ('active', 'trialing', 'past_due') THEN
              SELECT 10 + (COALESCE(map_pack_count, 0) * 10) INTO cap
              FROM teams
              WHERE id = NEW.team_id;
          ELSE
              cap := 3;
          END IF;

          IF active_count >= cap THEN
              RAISE EXCEPTION 'Team has reached the maximum of % active maps', cap;
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER check_map_cap
        BEFORE INSERT ON maps
        FOR EACH ROW EXECUTE FUNCTION enforce_map_cap();
    SQL

    alter_table(:teams) do
      set_column_default :billing_state, 'solo'
    end

    from(:teams).where(billing_state: 'active', person_cap: 8).update(
      billing_state: 'solo'
    )

    drop_column :teams, :person_cap
  end
end
