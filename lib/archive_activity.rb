# frozen_string_literal: true

require_relative 'record_event'

# Archives an activity: it leaves the map and its history stays. An activity
# that still has steps is not archived; they are archived or moved first.
module ArchiveActivity
  Result = Struct.new(:success?, :error, keyword_init: true)
  HAS_STEPS = 'Cannot archive an activity that has tasks'

  def self.call(activity:, actor:, now:)
    return Result.new(success?: false, error: HAS_STEPS) if Task.where(activity_id: activity.id, archived_at: nil).any?

    DB.transaction do
      activity.update(archived_at: now)
      RecordEvent.call(actor_id: actor.id, entity: activity, action: 'archived', after_state: { name: activity.name })
    end
    Result.new(success?: true)
  end
end
