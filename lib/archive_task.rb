# frozen_string_literal: true

require_relative 'record_event'

# Archives a step: it leaves the map and its history stays. A step that still
# has stories is not archived; they are archived or moved first.
module ArchiveTask
  Result = Struct.new(:success?, :error, keyword_init: true)
  HAS_STORIES = 'Cannot archive a step that has stories'

  def self.call(task:, actor:, now:)
    return Result.new(success?: false, error: HAS_STORIES) if Story.where(task_id: task.id, archived_at: nil).any?

    DB.transaction do
      task.update(archived_at: now)
      RecordEvent.call(actor_id: actor.id, entity: task, action: 'archived', after_state: { name: task.name })
    end
    Result.new(success?: true)
  end
end
