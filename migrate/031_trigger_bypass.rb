# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE OR REPLACE FUNCTION prevent_event_mutation()
      RETURNS TRIGGER AS $$
      BEGIN
          IF TG_OP = 'DELETE' AND current_setting('app.allow_team_deletion', true) = 'true' THEN
              RETURN OLD;
          END IF;
          RAISE EXCEPTION 'events table is append-only: % not allowed', TG_OP;
          RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_min_one_persona()
      RETURNS TRIGGER AS $$
      DECLARE
          remaining integer;
      BEGIN
          IF current_setting('app.allow_team_deletion', true) = 'true' THEN
              RETURN OLD;
          END IF;

          SELECT COUNT(*) INTO remaining
          FROM activity_personas
          WHERE activity_id = OLD.activity_id;

          IF remaining = 0 THEN
              RAISE EXCEPTION 'Activity must have at least one persona';
          END IF;

          RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE OR REPLACE FUNCTION delete_team_data(p_team_id uuid)
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public
      AS $$
      BEGIN
          PERFORM set_config('app.allow_team_deletion', 'true', true);

          DELETE FROM events WHERE team_id = p_team_id;
          DELETE FROM story_assignments WHERE team_id = p_team_id;
          DELETE FROM scenarios WHERE story_id IN (SELECT id FROM stories WHERE team_id = p_team_id);
          DELETE FROM stories WHERE team_id = p_team_id;
          DELETE FROM release_slices WHERE team_id = p_team_id;
          DELETE FROM tasks WHERE team_id = p_team_id;
          DELETE FROM activity_personas WHERE team_id = p_team_id;
          DELETE FROM activities WHERE team_id = p_team_id;
          DELETE FROM personas WHERE team_id = p_team_id;
          DELETE FROM map_view_prefs WHERE map_id IN (SELECT id FROM maps WHERE team_id = p_team_id);
          DELETE FROM maps WHERE team_id = p_team_id;
          DELETE FROM team_constraints WHERE team_id = p_team_id;
      END;
      $$;
    SQL
  end

  down do
    run <<~SQL
      CREATE OR REPLACE FUNCTION prevent_event_mutation()
      RETURNS TRIGGER AS $$
      BEGIN
          RAISE EXCEPTION 'events table is append-only: % not allowed', TG_OP;
          RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE OR REPLACE FUNCTION enforce_min_one_persona()
      RETURNS TRIGGER AS $$
      DECLARE
          remaining integer;
      BEGIN
          SELECT COUNT(*) INTO remaining
          FROM activity_personas
          WHERE activity_id = OLD.activity_id;

          IF remaining = 0 THEN
              RAISE EXCEPTION 'Activity must have at least one persona';
          END IF;

          RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE OR REPLACE FUNCTION delete_team_data(p_team_id uuid)
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public
      AS $$
      BEGIN
          ALTER TABLE events DISABLE TRIGGER enforce_append_only;
          DELETE FROM events WHERE team_id = p_team_id;
          ALTER TABLE events ENABLE TRIGGER enforce_append_only;

          DELETE FROM story_assignments WHERE team_id = p_team_id;
          DELETE FROM scenarios WHERE story_id IN (SELECT id FROM stories WHERE team_id = p_team_id);
          DELETE FROM stories WHERE team_id = p_team_id;
          DELETE FROM release_slices WHERE team_id = p_team_id;
          DELETE FROM tasks WHERE team_id = p_team_id;

          ALTER TABLE activity_personas DISABLE TRIGGER check_min_one_persona;
          DELETE FROM activity_personas WHERE team_id = p_team_id;
          DELETE FROM activities WHERE team_id = p_team_id;
          ALTER TABLE activity_personas ENABLE TRIGGER check_min_one_persona;

          DELETE FROM personas WHERE team_id = p_team_id;
          DELETE FROM map_view_prefs WHERE map_id IN (SELECT id FROM maps WHERE team_id = p_team_id);
          DELETE FROM maps WHERE team_id = p_team_id;
          DELETE FROM team_constraints WHERE team_id = p_team_id;
      END;
      $$;
    SQL
  end
end
