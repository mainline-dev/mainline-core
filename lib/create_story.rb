# frozen_string_literal: true

require_relative 'record_event'
require_relative 'resource_cap'

module CreateStory
  Result = Struct.new(:success?, :errors, :story, keyword_init: true)

  def self.call(map:, team:, actor:, person:, title:, task_id:)
    errors = validate(map, title, task_id)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    story = nil
    DB.transaction do
      position = (Story.where(task_id: task_id, archived_at: nil).max(:position) || 0) + 1000
      story = Story.create(
        task_id: task_id, map_id: map.id, team_id: team.id, title: title, description: '',
        position: position, created_by_id: person.id
      )
      RecordEvent.call(
        actor_id:    actor.id,
        entity:      story,
        action:      'created',
        after_state: { title: title, task_id: task_id, position: position }
      )
    end

    Result.new(success?: true, errors: [], story: story)
  end

  def self.validate(map, title, task_id)
    errors = []
    errors << 'This map has reached its story limit' if ResourceCap.stories_per_map(Story.where(map_id: map.id).count) == :blocked
    errors << 'Title is required' unless title
    errors << 'Title must be 200 characters or fewer' if title && title.length > 200
    errors << 'Step is required' unless task_id
    errors << 'Step not found' if task_id && Task.where(id: task_id, map_id: map.id, archived_at: nil).none?
    errors
  end
  private_class_method :validate
end
