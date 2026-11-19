# frozen_string_literal: true

require_relative 'never_pulled'

# A new team's first steps, in the order the team page lists them, each done
# or not by what the team has done so far. Once a story has been released the
# team is past its first steps, and there are none.
module FirstRun
  # The steps every team needs before its list can be put away. A map is not
  # named: nothing is promoted or sliced without one. Connecting a coding
  # agent is optional, and the figure only comes with time.
  NEEDED = %i[promote slice start].freeze

  # Whether the steps given are those of a team that has done what it needs
  # to. Not so for a team past its first steps, which has none.
  def self.settled?(steps)
    !steps.nil? && steps.values_at(*NEEDED).all?
  end

  def self.for(team, now: Time.now)
    stories = Story.where(team_id: team.id)
    return if stories.where(status: 'released').any?

    exhibits = MuseumItem.where(team_id: team.id)
    {
      # A new map, or a Jira CSV or Mainline file in the museum, starts it.
      map:     Map.where(team_id: team.id).any? || exhibits.any?,
      promote: exhibits.exclude(promoted_at: nil).any?,
      slice:   ReleaseSlice.where(team_id: team.id).any?,
      start:   stories.exclude(status: 'planned').any?,
      # Someone has given a coding agent the team, at any time.
      agent:   DB[:oauth_grant_teams].where(team_id: team.id).any?,
      figure:  !NeverPulled.percent(team.id, now: now).nil?
    }
  end
end
