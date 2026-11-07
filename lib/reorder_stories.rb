# frozen_string_literal: true

require 'securerandom'
require_relative 'rebalance_positions'
require_relative 'record_event'

module ReorderStories
  def self.call(task:, story_ids:, actor:, release_slice_id: nil, map_id: nil)
    scope = map_id ? { map_id: map_id } : { task_id: task.id }
    moving_stories = Story.where(id: story_ids, archived_at: nil, **scope).all
    return :not_found unless moving_stories.size == story_ids.size

    cross_task = moving_stories.reject { |s| s.task_id == task.id }
    target_slice_id = release_slice_id.to_s.empty? ? nil : release_slice_id
    error = validate(task, moving_stories, cross_task, release_slice_id, target_slice_id)
    return error if error

    DB.transaction do
      apply(task, story_ids, cross_task, actor, target_slice_id, slice_change: !release_slice_id.nil?)
    end

    nil
  end

  def self.apply(task, story_ids, cross_task, actor, target_slice_id, slice_change:)
    correlation_id = SecureRandom.uuid
    move_to_task(cross_task, task, actor, correlation_id)

    all_stories = Story.where(task_id: task.id, archived_at: nil).all
    others = all_stories.reject { |s| story_ids.include?(s.id) }.sort_by(&:position)
    RebalancePositions.reorder(
      table: :stories, records: all_stories, ordered_ids: story_ids + others.map(&:id),
      moved_ids: story_ids, actor: actor, correlation_id: correlation_id
    )
    return unless slice_change

    moved = all_stories.select { |s| story_ids.include?(s.id) }.sort_by { |s| story_ids.index(s.id) }
    change_slice(moved, target_slice_id, actor, correlation_id)
  end

  def self.validate(task, moving_stories, cross_task, release_slice_id, target_slice_id)
    return :released_story if cross_task.any? { |s| released?(s) }
    return unless release_slice_id
    return :released_story if moving_stories.any? { |s| s.release_slice_id != target_slice_id && released?(s) }

    :invalid_slice if target_slice_id && ReleaseSlice.where(id: target_slice_id, map_id: task.map_id).none?
  end

  def self.released?(story)
    story.status == 'released'
  end

  def self.move_to_task(stories, task, actor, correlation_id)
    stories.each_with_index do |story, i|
      old_task_id = story.task_id
      DB[:stories].where(id: story.id).update(task_id: task.id, position: -(10_000 + i))
      RecordEvent.call(
        actor_id: actor.id, entity: story.refresh, action: 'task_changed',
        before_state: { task_id: old_task_id },
        after_state: { task_id: task.id },
        correlation_id: correlation_id
      )
    end
  end

  def self.change_slice(stories, target_slice_id, actor, correlation_id)
    stories.each do |story|
      old_slice_id = story.release_slice_id
      next if old_slice_id == target_slice_id

      DB[:stories].where(id: story.id).update(release_slice_id: target_slice_id)
      RecordEvent.call(
        actor_id: actor.id, entity: story.refresh, action: 'slice_changed',
        before_state: { release_slice_id: old_slice_id },
        after_state: { release_slice_id: target_slice_id },
        correlation_id: correlation_id
      )
    end
  end

  private_class_method :apply, :validate, :released?, :move_to_task, :change_slice
end
