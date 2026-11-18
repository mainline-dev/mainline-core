# frozen_string_literal: true

require_relative 'record_event'
require_relative 'unassign_person'

# Archives a working member of a team: they have left from now, recorded with
# their name, and they come off every story of the team's they were on, the
# way anyone is taken off a story. So a story left with nobody goes back to
# planned, and a pair left with one person is recorded as that person working
# alone.
module ArchiveMember
  def self.call(membership:, actor:, now:)
    DB.transaction do
      membership.update(left_at: now)
      person = Person[membership.person_id]
      RecordEvent.call(actor_id: actor.id, entity: membership, action: 'member_archived',
        before_state: { person_id: person.id, name: person.name })
      StoryAssignment.where(person_id: person.id, team_id: membership.team_id).each do |assignment|
        UnassignPerson.call(story: Story[assignment.story_id], assignment: assignment, actor: actor)
      end
    end
  end
end
