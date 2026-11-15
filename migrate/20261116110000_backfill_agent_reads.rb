# frozen_string_literal: true

# The AGENT chip now comes from the read log. Stories were flagged from
# 2026-06-07 but reads were only logged from 2026-07-11, so a story read in
# between has the flag and no read. Give each such story one read by its
# team's coding agent, marked as backfilled. It names nobody on the story, so
# the pairing matrix counts nothing from it. Story events are stored with the
# entity type 'storie' (RecordEvent drops the last "s" of the table name).
Sequel.migration do
  up do
    run "SELECT set_config('app.rls_bypass', 'true', true)"
    run <<~SQL
      INSERT INTO events (team_id, map_id, actor_id, entity_type, entity_id, action, after_state)
      SELECT s.team_id, s.map_id, t.mcp_actor_id, 'storie', s.id, 'agent_read', '{"backfilled": true}'::jsonb
      FROM stories s
      JOIN teams t ON t.id = s.team_id
      WHERE s.agent_assisted
        AND NOT EXISTS (
          SELECT 1 FROM events e
          WHERE e.entity_type = 'storie' AND e.entity_id = s.id AND e.action = 'agent_read'
        )
    SQL
  end

  down do
    # Nothing to undo: events are append-only, and a backfilled read says
    # only what the flag said.
  end
end
