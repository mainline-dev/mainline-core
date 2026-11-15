# frozen_string_literal: true

# The team's coding agent: the actor its agent reads are recorded with. Every
# team has one from its creation, so looking it up changes nothing.
module McpActor
  def self.id_for(team_id)
    Team[team_id].mcp_actor_id
  end
end
