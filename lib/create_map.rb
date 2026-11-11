# frozen_string_literal: true

require_relative 'record_event'
require_relative 'resource_cap'

# Creates a story map for a team, after the team's other maps, and records it.
# The one way maps are made. A team near its map limit is warned; one at the
# limit is refused.
module CreateMap
  Result = Struct.new(:success?, :errors, :created, :warning, keyword_init: true)

  def self.call(team:, actor:, name:)
    count = Map.where(team_id: team.id).count
    cap = ResourceCap.maps_per_team(count)
    errors = validate(name, cap)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    map = nil
    DB.transaction do
      position = (Map.where(team_id: team.id).max(:position) || 0) + 1000
      map = Map.create(team_id: team.id, name: name, position: position)
      RecordEvent.call(actor_id: actor.id, entity: map, action: 'created', map_id: map.id,
        after_state: { name: map.name, position: map.position })
    end
    warning = "This team has #{count} maps. Consider archiving unused ones." if cap == :warning
    Result.new(success?: true, errors: [], created: map, warning: warning)
  end

  def self.validate(name, cap)
    errors = []
    errors << 'This team has reached its map limit' if cap == :blocked
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors
  end
  private_class_method :validate
end
