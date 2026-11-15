# frozen_string_literal: true

require_relative 'record_event'
require_relative 'two_person_rule'

# A story's kickoff: the second person coming to it before the work. On a
# story two or more people started, it is those people, taken from the event
# that first had them on it together, and it stands from then on. On a
# story one person works on, that is someone else agreeing its scenarios,
# recorded as an event on the story. Anyone working on the team can agree
# them except whoever changed them last. A scenario added, edited or removed
# afterwards leaves the kickoff reading as changed until someone agrees
# again. It is shown and never enforced.
module Kickoff
  AGREED = 'scenarios_agreed'
  CHANGES = %w[scenario_added scenario_edited scenario_removed].freeze
  REFUSALS = {
    'released'     => 'The scenarios of a released story cannot be agreed.',
    'no-scenarios' => 'This story has no scenarios to agree.',
    'not-working'  => 'Only people working on the team can agree scenarios.',
    'own-change'   => 'You last changed these scenarios. A kickoff needs someone else to agree them.'
  }.freeze
  State = Struct.new(:kind, :people, keyword_init: true)
  Result = Struct.new(:success?, :error, :reason, keyword_init: true)

  def self.for(story)
    together = started_together(story)
    return State.new(kind: :together, people: together) if together

    agreed = story_events(story, AGREED).reverse(:event_no).first
    return State.new(kind: :none, people: []) unless agreed

    changed = story_events(story, CHANGES).where { event_no > agreed.event_no }.any?
    State.new(kind: changed ? :changed : :agreed, people: Person.where(actor_id: agreed.actor_id).all)
  end

  # The people on the story when it first had two or more, by name, if it
  # ever did.
  def self.started_together(story)
    first = story_events(story, 'collaboration_changed').order(:event_no).all
      .find { |event| TwoPersonRule::TOGETHER.include?(event.after_state['mode']) }
    Person.where(id: first.after_state['person_ids']).order(:name).all if first
  end
  private_class_method :started_together

  def self.can_agree?(story, person)
    refusal(story, person).nil?
  end

  def self.agree(story:, person:)
    reason = refusal(story, person)
    return Result.new(success?: false, error: REFUSALS.fetch(reason), reason: reason) if reason

    DB.transaction { RecordEvent.call(actor_id: person.actor_id, entity: story, action: AGREED) }
    Result.new(success?: true)
  end

  # The short name of why this person cannot agree the story's scenarios, if
  # they cannot.
  def self.refusal(story, person)
    return 'released' if story.status == 'released'
    return 'no-scenarios' if Scenario.where(story_id: story.id).empty?
    return 'not-working' unless working_on_team?(story, person)

    'own-change' if story_events(story, CHANGES).reverse(:event_no).get(:actor_id) == person.actor_id
  end
  private_class_method :refusal

  def self.working_on_team?(story, person)
    TeamMembership.where(team_id: story.team_id, person_id: person.id, working: true, left_at: nil).any?
  end
  private_class_method :working_on_team?

  def self.story_events(story, action)
    Event.where(entity_type: RecordEvent.entity_type_for(Story), entity_id: story.id, action: action)
  end
  private_class_method :story_events
end
