# frozen_string_literal: true

require_relative 'record_event'

# Writes down that people were walked through what was built on a story: an
# event on the story naming who attended. The one way a walkthrough is
# recorded. A story can be walked through more than once. The people attending
# are other than the people on the story, who are the ones showing it.
module RecordWalkthrough
  ACTION = 'walked_through'
  Result = Struct.new(:success?, :error, :reason, keyword_init: true)
  NOT_DEPLOYED = 'A walkthrough can be recorded once the story has been deployed.'

  def self.call(story:, actor:, attendee_ids:)
    error, reason = refusal(story, attendee_ids)
    return Result.new(success?: false, error: error, reason: reason) if error

    DB.transaction do
      RecordEvent.call(
        actor_id: actor.id, entity: story, action: ACTION,
        after_state: { attendee_ids: attendee_ids }
      )
    end
    Result.new(success?: true)
  end

  # Why this walkthrough cannot be recorded, and the reason's short name, if
  # there is one.
  def self.refusal(story, attendee_ids)
    return [NOT_DEPLOYED, 'not-deployed'] unless story.deploy_count.positive?

    on_story = StoryAssignment.where(story_id: story.id, person_id: attendee_ids).first
    return unless on_story

    ["#{Person[on_story.person_id].name} is assigned to this story, so cannot attend its walkthrough.",
     'attendee-on-story']
  end
  private_class_method :refusal
end
