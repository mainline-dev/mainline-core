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
    applies?(team) && seen_by_two([story]).empty?
  end

  # The stories waiting for a walkthrough: active, deployed, worked on by one
  # person and not walked through. The longest since its last deploy is first.
  def self.awaiting(team)
    return [] unless applies?(team)

    stories = Story.where(team_id: team.id, status: 'active', archived_at: nil).exclude(deploy_count: 0)
      .order(:last_deployed_at).all
    seen = seen_by_two(stories)
    stories.reject { |story| seen.include?(story.id) }
  end

  # Which of these stories two people have seen, by ID.
  def self.seen_by_two(stories)
    Event.where(entity_type: RecordEvent.entity_type_for(Story), entity_id: stories.map(&:id),
      action: ['collaboration_changed', RecordWalkthrough::ACTION]).all
      .select { |event| event.action == RecordWalkthrough::ACTION || TOGETHER.include?(event.after_state['mode']) }
      .to_set(&:entity_id)
  end
  private_class_method :seen_by_two
end
