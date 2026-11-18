# frozen_string_literal: true

require_relative 'record_event'

# Changes one of a team's own settings, its timezone or its holiday region,
# and records what it was and became, in one transaction, so the team never
# changes without its record. Saving a setting as it already is records
# nothing. Only these settings change this way.
module ChangeTeamField
  FIELDS = %i[timezone holiday_region].freeze

  def self.call(team:, actor:, field:, value:)
    raise ArgumentError, "#{field} is not changed this way" unless FIELDS.include?(field)

    DB.transaction do
      was = team[field]
      team.update(field => value)
      next if was == value

      RecordEvent.call(actor_id: actor.id, entity: team, action: 'updated', team_id: team.id,
        before_state: { field => was }, after_state: { field => value })
    end
  end
end
