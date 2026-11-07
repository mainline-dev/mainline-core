# frozen_string_literal: true

require 'securerandom'
require_relative 'rebalance_positions'
require_relative 'record_event'

module ReorderTasks
  def self.call(activity:, task_ids:, actor:, map_id:)
    tasks = Task.where(id: task_ids, map_id: map_id, archived_at: nil).all
    return :not_found unless tasks.size == task_ids.size

    correlation_id = SecureRandom.uuid
    DB.transaction do
      move_to_activity(tasks.reject { |t| t.activity_id == activity.id }, activity, actor, correlation_id)

      all_tasks = Task.where(activity_id: activity.id, archived_at: nil).all
      others = all_tasks.reject { |t| task_ids.include?(t.id) }.sort_by(&:position)
      RebalancePositions.reorder(
        table: :tasks, records: all_tasks, ordered_ids: task_ids + others.map(&:id),
        moved_ids: task_ids, actor: actor, correlation_id: correlation_id
      )
    end

    nil
  end

  def self.move_to_activity(tasks, activity, actor, correlation_id)
    tasks.each do |task|
      old_activity_id = task.activity_id
      DB[:tasks].where(id: task.id).update(activity_id: activity.id, position: -rand(1..10_000))
      RecordEvent.call(
        actor_id: actor.id, entity: task.refresh, action: 'task_moved',
        before_state: { activity_id: old_activity_id },
        after_state:  { activity_id: activity.id },
        correlation_id: correlation_id
      )
    end
  end
  private_class_method :move_to_activity
end
