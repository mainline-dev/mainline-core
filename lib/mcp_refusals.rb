# frozen_string_literal: true

# What an MCP tool says when it can't read a map, story or team. Only the
# person's own teams, and the teams given, are named; anything else gets the
# answer for nothing there, so a refusal never confirms another team's story.
module McpRefusals
  NO_STORY = 'No story with that ID. Use an ID from get_map, or the 8-character ID on the card.'
  NO_MAP = 'No map with that ID. Use an ID from list_maps.'
  NO_TEAM = 'No team with that ID among those this coding agent can read. list_maps names them.'
  AMBIGUOUS = 'More than one story starts with that ID. Use the full ID from get_map.'
  CODING_AGENTS_PAGE = "#{ENV.fetch('BASE_URL')}/profile/coding-agents".freeze

  def self.text(status, team_id, not_found)
    name = (Team[team_id]&.name if team_id)
    case status
    when :withheld then "That is on #{name}, a team you did not give this coding agent. " \
                        "To let it read #{name}, give it that team on the Coding agents page: #{CODING_AGENTS_PAGE}"
    when :suspended then "#{name} is suspended, so its maps and stories can't be read."
    when :ambiguous then AMBIGUOUS
    else not_found
    end
  end
end
