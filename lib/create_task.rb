# frozen_string_literal: true

require_relative 'record_event'

module CreateTask
  Result = Struct.new(:success?, :errors, :task, keyword_init: true)

  def self.call(map:, team:, actor:, name:, activity_id:)
    errors = validate(map, name, activity_id)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    task = nil
    DB.transaction do
      position = (Task.where(activity_id: activity_id).max(:position) || 0) + 1000
      task = Task.create(activity_id: activity_id, map_id: map.id, team_id: team.id, name: name, position: position)
      RecordEvent.call(
        actor_id:    actor.id,
        entity:      task,
        action:      'created',
        after_state: { name: name, activity_id: activity_id, position: position }
      )
    end

    Result.new(success?: true, errors: [], task: task)
  end

  def self.validate(map, name, activity_id)
    errors = []
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors << 'Activity is required' unless activity_id
    errors << 'Activity not found' if activity_id && Activity.where(id: activity_id, map_id: map.id, archived_at: nil).none?
    errors
  end
  private_class_method :validate
end
