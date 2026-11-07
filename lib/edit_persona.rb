# frozen_string_literal: true

require_relative 'record_event'

module EditPersona
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(persona:, actor:, name:, description:, activity_ids:)
    errors = validate(name)
    errors = orphan_errors(persona, activity_ids) if errors.empty?
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      before = { name: persona.name, description: persona.description, activity_ids: linked_activity_ids(persona) }
      persona.update(name: name, description: description)
      relink_activities(persona, activity_ids)
      RecordEvent.call(
        actor_id:     actor.id,
        entity:       persona,
        action:       'edited',
        before_state: before,
        after_state:  { name: name, description: description, activity_ids: activity_ids }
      )
    end

    Result.new(success?: true, errors: [])
  end

  def self.validate(name)
    errors = []
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors
  end
  private_class_method :validate

  # Unlinking must not leave an active activity with no persona.
  def self.orphan_errors(persona, activity_ids)
    removed = linked_activity_ids(persona) - activity_ids
    return [] if removed.empty?

    Activity.where(id: removed, archived_at: nil)
      .exclude(id: ActivityPersona.exclude(persona_id: persona.id).select(:activity_id))
      .select_map(:name)
      .map { |n| "'#{n}' needs at least one persona" }
  end
  private_class_method :orphan_errors

  def self.linked_activity_ids(persona)
    ActivityPersona.where(persona_id: persona.id).select_map(:activity_id)
  end
  private_class_method :linked_activity_ids

  # Links to archived activities are kept; only active ones are replaced.
  def self.relink_activities(persona, activity_ids)
    active_activity_ids = Activity.where(map_id: persona.map_id, archived_at: nil).select(:id)
    ActivityPersona.where(persona_id: persona.id, activity_id: active_activity_ids).delete
    activity_ids.each do |aid|
      ActivityPersona.create(activity_id: aid, persona_id: persona.id, team_id: persona.team_id)
    end
  end
  private_class_method :relink_activities
end
