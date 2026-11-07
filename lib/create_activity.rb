# frozen_string_literal: true

require_relative 'record_event'

module CreateActivity
  Result = Struct.new(:success?, :errors, :activity, keyword_init: true)

  def self.call(map:, team:, actor:, name:, persona_ids:)
    errors = validate(map, name, persona_ids)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    activity = nil
    DB.transaction do
      position = (Activity.where(map_id: map.id).max(:position) || 0) + 1000
      correlation = SecureRandom.uuid
      activity = Activity.create(map_id: map.id, team_id: team.id, name: name, position: position)
      link_personas(activity, persona_ids, actor, correlation)
      RecordEvent.call(
        actor_id:       actor.id,
        entity:         activity,
        action:         'created',
        after_state:    { name: name, position: position, persona_ids: persona_ids },
        correlation_id: correlation
      )
    end

    Result.new(success?: true, errors: [], activity: activity)
  end

  def self.validate(map, name, persona_ids)
    errors = []
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors << 'Select at least one persona' if persona_ids.empty?
    if persona_ids.any? && Persona.where(id: persona_ids, map_id: map.id, archived_at: nil).count != persona_ids.length
      errors << 'One or more selected personas not found'
    end
    errors
  end
  private_class_method :validate

  def self.link_personas(activity, persona_ids, actor, correlation)
    persona_ids.each do |pid|
      ActivityPersona.create(activity_id: activity.id, persona_id: pid, team_id: activity.team_id)
      RecordEvent.call(
        actor_id:       actor.id,
        entity:         activity,
        action:         'persona_added',
        after_state:    { persona_id: pid },
        correlation_id: correlation
      )
    end
  end
  private_class_method :link_personas
end
