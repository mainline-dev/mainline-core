# frozen_string_literal: true

require_relative 'record_event'
require_relative 'record_walkthrough'

# A story can be released only if two people have seen it. Either two people
# were on it at some point while it was active, which its collaboration events
# show as they do for the solo log, or a walkthrough is recorded for it. The
# rule counts people and never asks how the code was written. A team with one
# working member has no second person, so it is never held to it, and a team
# can turn the rule off.
module TwoPersonRule
  REFUSAL = 'One person worked on this story. Record a walkthrough before releasing it.'
  REASON = 'needs-walkthrough'
  TOGETHER = %w[paired ensemble].freeze
  KEY = 'two_person_rule'
  LIMIT_KEY = 'walkthrough_limit'
  DEFAULT_LIMIT = 3
  LIMIT_RANGE = (1..10)
  # On the release event of an urgent story released before its walkthrough.
  BEFORE_WALKTHROUGH = 'before_walkthrough'

  # On for every team until it turns it off in its settings.
  def self.on?(team)
    TeamConstraint.for_team(team.id, KEY, default: 1) == 1
  end

  def self.applies?(team)
    on?(team) && TeamMembership.where(team_id: team.id, left_at: nil, working: true).count >= 2
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

  # How many stories may wait for a walkthrough before nobody on the team can
  # start another.
  def self.limit(team)
    TeamConstraint.for_team(team.id, LIMIT_KEY, default: DEFAULT_LIMIT)
  end

  # Urgent stories released before their walkthrough and not walked through
  # since, the longest released first.
  def self.walk_afterwards(team)
    return [] unless applies?(team)

    early = Event.where(team_id: team.id, entity_type: RecordEvent.entity_type_for(Story), action: 'released').all
      .select { |event| event.after_state[BEFORE_WALKTHROUGH] }.map(&:entity_id)
    stories = Story.where(id: early, status: 'released', archived_at: nil).order(:released_at).all
    seen = walked(stories)
    stories.reject { |story| seen.include?(story.id) }
  end

  # How many stories wait for a walkthrough: those awaiting one before release,
  # and urgent ones released before theirs.
  def self.waiting(team)
    awaiting(team).size + walk_afterwards(team).size
  end

  def self.at_limit?(team)
    waiting(team) >= limit(team)
  end

  def self.limit_refusal(team)
    waiting = waiting(team)
    return '1 story is waiting for a walkthrough. Walk it through before starting another.' if waiting == 1

    "#{waiting} stories are waiting for a walkthrough. Walk one through before starting another."
  end

  # Which of these stories had two or more people on them at some point, by ID.
  def self.together(stories)
    story_events(stories, 'collaboration_changed').select { |event| TOGETHER.include?(event.after_state['mode']) }
      .to_set(&:entity_id)
  end

  # Which of these stories have been walked through, by ID.
  def self.walked(stories)
    story_events(stories, RecordWalkthrough::ACTION).to_set(&:entity_id)
  end

  # Which of these stories two people have seen, by ID.
  def self.seen_by_two(stories)
    together(stories) | walked(stories)
  end

  def self.story_events(stories, action)
    Event.where(entity_type: RecordEvent.entity_type_for(Story), entity_id: stories.map(&:id), action: action).all
  end
  private_class_method :seen_by_two, :story_events
end
