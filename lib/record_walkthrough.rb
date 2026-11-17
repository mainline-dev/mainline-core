# frozen_string_literal: true

require_relative 'record_event'

# Writes down that people were walked through what was built on a story: an
# event on the story naming who attended and how many times the story had
# been deployed by then. The one way a walkthrough is recorded. A story can
# be walked through more than once. At least one person attends, each working
# on the team now and none on the story, since those are the ones showing it.
module RecordWalkthrough
  ACTION = 'walked_through'
  Result = Struct.new(:success?, :error, :reason, keyword_init: true)
  NOT_DEPLOYED = 'A walkthrough can be recorded once the story has been deployed.'
  NO_ATTENDEES = 'Tick who attended the walkthrough.'
  NOT_ON_TEAM = 'Only people working on this team can attend its walkthrough.'

  def self.call(story:, actor:, attendee_ids:)
    error, reason = refusal(story, attendee_ids)
    return Result.new(success?: false, error: error, reason: reason) if error

    DB.transaction do
      RecordEvent.call(
        actor_id: actor.id, entity: story, action: ACTION,
        after_state: { attendee_ids: attendee_ids, deploy_count: story.deploy_count }
      )
    end
    Result.new(success?: true)
  end

  # Why this walkthrough cannot be recorded, and the reason's short name, if
  # there is one.
  def self.refusal(story, attendee_ids)
    return [NOT_DEPLOYED, 'not-deployed'] unless story.deploy_count.positive?
    return [NO_ATTENDEES, 'no-attendees'] if attendee_ids.empty?
    return [NOT_ON_TEAM, 'attendee-not-on-team'] unless working_on_team?(story.team_id, attendee_ids)

    on_story = StoryAssignment.where(story_id: story.id, person_id: attendee_ids).first
    return unless on_story

    ["#{Person[on_story.person_id].name} is assigned to this story, so cannot attend its walkthrough.",
     'attendee-on-story']
  end

  # Whether everyone listed works on the team now, as the form offers them.
  def self.working_on_team?(team_id, attendee_ids)
    working = TeamMembership.where(team_id: team_id, person_id: attendee_ids, working: true, left_at: nil)
    working.count == attendee_ids.uniq.size
  end
  private_class_method :refusal, :working_on_team?
end
