# frozen_string_literal: true

module McpActor
  def self.id_for(team_id)
    team = Team[team_id]
    return team.mcp_actor_id if team.mcp_actor_id

    actor = Actor.create(kind: 'system', name: 'Coding agent')
    team.update(mcp_actor_id: actor.id)
    actor.id
  end
end
