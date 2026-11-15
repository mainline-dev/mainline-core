# frozen_string_literal: true

require_relative 'record_event'
require_relative 'record_walkthrough'

# A story can be released only if two people have seen it. Either two people
# were on it at some point while it was active, which its collaboration events
# show as they do for the solo log, or a walkthrough is recorded for it. The
# rule counts people and never asks how the code was written. A team with one
# working member has no second person, so it is never held to it.
module TwoPersonRule
  REFUSAL = 'One person worked on this story. Record a walkthrough before releasing it.'
  REASON = 'needs-walkthrough'
  TOGETHER = %w[paired ensemble].freeze

  def self.applies?(team)
    TeamMembership.where(team_id: team.id, left_at: nil, working: true).count >= 2
  end

  def self.blocks_release?(story, team)
    applies?(team) && !had_two_people?(story) && !walked_through?(story)
  end

  def self.walked_through?(story)
    story_events(story, RecordWalkthrough::ACTION).any?
  end

  def self.had_two_people?(story)
    story_events(story, 'collaboration_changed').all.any? { |event| TOGETHER.include?(event.after_state['mode']) }
  end

  def self.story_events(story, action)
    Event.where(entity_type: RecordEvent.entity_type_for(Story), entity_id: story.id, action: action)
  end
  private_class_method :story_events
end
