# frozen_string_literal: true

require_relative 'record_event'

# Adds an acceptance scenario (given, when, then) to the end of a story's list
# and records it. The one way scenarios are added.
module AddScenario
  Result = Struct.new(:success?, :errors, :scenario, keyword_init: true)
  MAX_LENGTH = 100

  def self.call(story:, actor:, given_text:, when_text:, then_text:)
    errors = errors(given_text, when_text, then_text)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    scenario = nil
    DB.transaction do
      position = (Scenario.where(story_id: story.id).max(:position) || 0) + 1000
      scenario = Scenario.create(story_id: story.id, given_text: given_text, when_text: when_text, then_text: then_text,
        position: position)
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'scenario_added')
    end
    Result.new(success?: true, errors: [], scenario: scenario)
  end

  # What is wrong with a scenario's parts, if anything.
  def self.errors(given_text, when_text, then_text)
    { 'Given' => given_text, 'When' => when_text, 'Then' => then_text }.flat_map { |part, text|
      [("#{part} is required" if text.to_s.empty?),
       ("#{part} must be #{MAX_LENGTH} characters or fewer" if text.to_s.length > MAX_LENGTH)]
    }.compact
  end
end
