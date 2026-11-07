# frozen_string_literal: true

Sequel.migration do
  up do
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
              cap := 2;
          END IF;

          IF active_count >= cap THEN
              RAISE EXCEPTION 'Team has reached the maximum of % active maps', cap;
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
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
    SQL
  end
end
