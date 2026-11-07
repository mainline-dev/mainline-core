# frozen_string_literal: true

require_relative 'record_event'

module ArchivePersona
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(persona:, actor:)
    errors = sole_activities(persona).map { |n| "'#{n}' needs at least one persona" }
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      ActivityPersona.where(persona_id: persona.id, activity_id: active_activities(persona).select(:id)).delete
      persona.update(archived_at: Time.now)
      RecordEvent.call(
        actor_id:    actor.id,
        entity:      persona,
        action:      'archived',
        after_state: { name: persona.name }
      )
    end

    Result.new(success?: true, errors: [])
  end

  # Names of active activities that only this persona covers.
  def self.sole_activities(persona)
    active_activities(persona)
      .where(id: ActivityPersona.where(persona_id: persona.id).select(:activity_id))
      .exclude(id: ActivityPersona.exclude(persona_id: persona.id).select(:activity_id))
      .select_map(:name)
  end
  private_class_method :sole_activities

  def self.active_activities(persona)
    Activity.where(map_id: persona.map_id, archived_at: nil)
  end
  private_class_method :active_activities
end
