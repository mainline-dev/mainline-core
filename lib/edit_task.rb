# frozen_string_literal: true

require_relative 'record_event'

module EditTask
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(task:, actor:, name:, activity_id:)
    errors = validate(task, name, activity_id)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      before = { name: task.name, activity_id: task.activity_id }
      updates = { name: name, activity_id: activity_id }
      updates[:position] = (Task.where(activity_id: activity_id).max(:position) || 0) + 1000 if activity_id != task.activity_id
      task.update(updates)
      RecordEvent.call(
        actor_id:     actor.id,
        entity:       task,
        action:       'edited',
        before_state: before,
        after_state:  { name: name, activity_id: activity_id }
      )
    end

    Result.new(success?: true, errors: [])
  end

  def self.validate(task, name, activity_id)
    errors = []
    errors << 'Name is required' unless name
    errors << 'Name must be 100 characters or fewer' if name && name.length > 100
    errors << 'Activity is required' unless activity_id
    errors << 'Activity not found' if activity_id && Activity.where(id: activity_id, map_id: task.map_id, archived_at: nil).none?
    errors
  end
  private_class_method :validate
end
