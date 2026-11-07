# frozen_string_literal: true

require_relative 'record_event'

# Archives a story: it leaves the map and its history stays. Released stories,
# and stories someone is assigned to, are not archived.
module ArchiveStory
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(story:, actor:)
    error = refusal(story)
    return Result.new(success?: false, errors: [error]) if error

    DB.transaction do
      story.update(archived_at: Time.now)
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'archived', after_state: { status: story.status })
    end
    Result.new(success?: true, errors: [])
  end

  def self.refusal(story)
    if story.status == 'released'
      'Released stories cannot be archived'
    elsif StoryAssignment.where(story_id: story.id).any?
      'Unassign everyone before archiving'
    end
  end
  private_class_method :refusal
end
