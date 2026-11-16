# frozen_string_literal: true

# Who may open a team's maps and stories. The map pages, the teams a person
# can give a coding agent, and every MCP request ask this one rule, so an
# agent reads exactly what its person could open in the browser.
module MapAccess
  # Whether the membership's team's maps are open to its person.
  def self.open_to?(membership)
    !membership.nil? && membership.left_at.nil? && membership.working
  end

  # The teams whose maps are open to the person.
  def self.team_ids_for(person_id)
    TeamMembership.where(person_id: person_id).all.select { |membership| open_to?(membership) }
      .map(&:team_id)
  end
end
