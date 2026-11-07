# frozen_string_literal: true

require 'securerandom'
require_relative 'record_event'

module MoveActivity
  def self.call(activity:, direction:, actor:)
    activities = Activity
      .where(map_id: activity.map_id, archived_at: nil)
      .order(:position)
      .all

    idx = activities.index { |a| a.id == activity.id }
    return :not_found unless idx

    target_idx = direction == 'left' ? idx - 1 : idx + 1
    return :no_adjacent if target_idx.negative? || target_idx >= activities.length

    swap(activity, activities[target_idx], actor)
    nil
  end

  def self.swap(activity, adjacent, actor)
    old_pos = activity.position
    new_pos = adjacent.position
    correlation_id = SecureRandom.uuid

    DB.transaction do
      DB[:activities].where(id: activity.id).update(position: -1)
      DB[:activities].where(id: adjacent.id).update(position: -2)
      DB[:activities].where(id: activity.id).update(position: new_pos)
      DB[:activities].where(id: adjacent.id).update(position: old_pos)

      record_reorder(activity, old_pos, new_pos, actor, correlation_id)
      record_reorder(adjacent, new_pos, old_pos, actor, correlation_id)
    end
  end

  def self.record_reorder(activity, from, to, actor, correlation_id)
    RecordEvent.call(
      actor_id: actor.id, entity: activity.refresh, action: 'reordered',
      before_state: { position: from },
      after_state:  { position: to },
      correlation_id: correlation_id
    )
  end

  private_class_method :swap, :record_reorder
end
