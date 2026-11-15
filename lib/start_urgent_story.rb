# frozen_string_literal: true

require_relative 'assign_person'
require_relative 'urgent_story'

# Starts a story as the team's urgent story: records why, then puts the person
# on it, whatever they are already working on. One at a time per team, checked
# under a lock on the team, so two people can't both start one.
module StartUrgentStory
  Result = Struct.new(:success?, :error, :reason, keyword_init: true)

  REFUSALS = {
    'reason-needed' => 'Say why this story is urgent.',
    'not-planned'   => 'Only a story that has not started can be started as urgent.',
    'urgent-taken'  => 'The team already has an urgent story. Release it before starting another.'
  }.freeze

  def self.call(story:, person_id:, reason:, team:, actor_id:)
    reason = reason.to_s.strip
    return refusal('reason-needed') if reason.empty?
    return refusal('not-planned') unless story.status == 'planned'

    result = nil
    DB.transaction do
      DB.get(Sequel.function(:pg_advisory_xact_lock, Sequel.function(:hashtext, "urgent:#{team.id}")))
      next result = refusal('urgent-taken') if UrgentStory.of(team)

      RecordEvent.call(actor_id: actor_id, entity: story, action: UrgentStory::ACTION, after_state: { reason: reason })
      assigned = AssignPerson.call(story: story, person_id: person_id, team: team, actor_id: actor_id)
      unless assigned.success?
        result = Result.new(success?: false, error: assigned.errors.first, reason: 'not-assigned')
        raise Sequel::Rollback
      end
      result = Result.new(success?: true)
    end
    result
  end

  def self.refusal(reason)
    Result.new(success?: false, error: REFUSALS.fetch(reason), reason: reason)
  end
  private_class_method :refusal
end
