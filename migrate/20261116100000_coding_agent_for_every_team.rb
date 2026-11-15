# frozen_string_literal: true

# Every team gets its coding agent when it is created. Teams made before that
# got theirs on their first agent read; this gives the rest theirs now, so a
# read never has to create one.
Sequel.migration do
  up do
    run "SELECT set_config('app.rls_bypass', 'true', true)"
    from(:teams).where(mcp_actor_id: nil).select_map(:id).each do |team_id|
      actor_id = from(:actors).returning(:id).insert(kind: 'system', name: 'Coding agent').first[:id]
      from(:teams).where(id: team_id).update(mcp_actor_id: actor_id)
    end
  end

  down do
    # Nothing to undo: a coding agent with no reads is harmless.
  end
end
