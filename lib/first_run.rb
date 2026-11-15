# frozen_string_literal: true

require_relative 'never_pulled'

# A new team's first steps, in the order the team page lists them, each done
# or not by what the team has done so far. Once a story has been released the
# team is past its first steps, and there are none.
module FirstRun
  def self.for(team, now: Time.now)
    stories = Story.where(team_id: team.id)
    return if stories.where(status: 'released').any?

    exhibits = MuseumItem.where(team_id: team.id)
    {
      import:  exhibits.exclude(source: 'mainline').any?,
      promote: exhibits.exclude(promoted_at: nil).any?,
      slice:   ReleaseSlice.where(team_id: team.id).any?,
      start:   stories.exclude(status: 'planned').any?,
      agent:   !team.mcp_token.nil?,
      figure:  !NeverPulled.percent(team.id, now: now).nil?
    }
  end
end
