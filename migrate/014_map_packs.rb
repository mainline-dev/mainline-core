# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :map_pack_count, :integer, default: 0, null: false

    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_map_cap()
      RETURNS TRIGGER AS $$
      DECLARE
          active_count integer;
          cap integer;
      BEGIN
          SELECT COUNT(*) INTO active_count
          FROM maps
          WHERE team_id = NEW.team_id
            AND archived_at IS NULL;

          SELECT 10 + (COALESCE(map_pack_count, 0) * 10) INTO cap
          FROM teams
          WHERE id = NEW.team_id;

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
      BEGIN
          SELECT COUNT(*) INTO active_count
          FROM maps
          WHERE team_id = NEW.team_id
            AND archived_at IS NULL;

          IF active_count >= 10 THEN
              RAISE EXCEPTION 'Team has reached the maximum of 10 active maps';
          END IF;

          RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    drop_column :teams, :map_pack_count
  end
end
