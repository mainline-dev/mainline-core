# frozen_string_literal: true

Sequel.migration do
  up do
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

        DELETE FROM tracked_branches WHERE monitored_repo_id IN
          (SELECT id FROM monitored_repos WHERE team_id = p_team_id);
        DELETE FROM monitored_repos WHERE team_id = p_team_id;

        DELETE FROM story_notes WHERE team_id = p_team_id;
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
      $$
    SQL
  end

  down do
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
      $$
    SQL
  end
end
