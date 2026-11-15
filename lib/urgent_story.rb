# frozen_string_literal: true

require_relative 'record_event'

# A team's urgent story: a security patch, a broken build, a rotated key. It is
# the story marked urgent, until it is released. A team has one at a time.
module UrgentStory
  ACTION = 'marked_urgent'

  def self.of(team)
    marked = Event.where(team_id: team.id, entity_type: RecordEvent.entity_type_for(Story), action: ACTION).select(:entity_id)
    Story.where(id: marked, archived_at: nil).exclude(status: 'released').first
  end

  def self.urgent?(story)
    story.status != 'released' &&
      Event.where(entity_type: RecordEvent.entity_type_for(Story), entity_id: story.id, action: ACTION).any?
  end
end
