# frozen_string_literal: true

require_relative 'assign_person'
require_relative 'record_event'

# Takes a person off a story and records it. An active story that nobody is
# left on goes back to planned; one that people are still on records the
# change in how it is worked, such as a pair becoming one person alone. A
# released story's people stay as they were when it went out.
module UnassignPerson
  Result = Struct.new(:success?, :error, keyword_init: true)
  RELEASED = 'Cannot modify a released story'

  def self.call(story:, assignment:, actor:)
    return Result.new(success?: false, error: RELEASED) if story.status == 'released'

    DB.transaction do
      assignment.destroy
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'person_unassigned',
        before_state: { person_id: assignment.person_id })
      remaining = StoryAssignment.where(story_id: story.id).count
      if remaining.zero? && story.status == 'active'
        story.update(status: 'planned')
        RecordEvent.call(actor_id: actor.id, entity: story, action: 'deactivated', after_state: { reason: 'no_assignees' })
      elsif story.status == 'active'
        AssignPerson.record_collaboration_change(story, actor.id, remaining + 1, remaining)
      end
    end
    Result.new(success?: true)
  end
end
