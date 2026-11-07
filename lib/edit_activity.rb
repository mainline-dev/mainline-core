# frozen_string_literal: true

require_relative 'record_event'

module EditActivity
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(activity:, actor:, name:, persona_ids:)
    errors = validate(activity, name, persona_ids)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      before = { name: activity.name, persona_ids: linked_persona_ids(activity) }
      activity.update(name: name)
      relink_personas(activity, persona_ids)
      RecordEvent.call(
        actor_id:     actor.id,
        entity:       activity,
        action:       'edited',
        before_state: before,
        after_state:  { name: name, persona_ids: persona_ids }
      )
    end

    Result.new(success?: true, errors: [])
  end

  def self.validate(activity, name, persona_ids)
    errors = []
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors << 'Select at least one persona' if persona_ids.empty?
    if persona_ids.any? && active_personas(activity).where(id: persona_ids).count != persona_ids.length
      errors << 'One or more selected personas not found'
    end
    errors
  end
  private_class_method :validate

  def self.linked_persona_ids(activity)
    ActivityPersona.where(activity_id: activity.id).select_map(:persona_id)
  end
  private_class_method :linked_persona_ids

  # Links to archived personas are kept; only active ones are replaced.
  def self.relink_personas(activity, persona_ids)
    ActivityPersona.where(activity_id: activity.id, persona_id: active_personas(activity).select(:id)).delete
    persona_ids.each do |pid|
      ActivityPersona.create(activity_id: activity.id, persona_id: pid, team_id: activity.team_id)
    end
  end
  private_class_method :relink_personas

  def self.active_personas(activity)
    Persona.where(map_id: activity.map_id, archived_at: nil)
  end
  private_class_method :active_personas
end
