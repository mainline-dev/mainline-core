# frozen_string_literal: true

require_relative 'record_event'

# Adds a named acceptance scenario (given, when, then) to the end of a story's list
# and records it. The one way scenarios are added.
module AddScenario
  Result = Struct.new(:success?, :errors, :scenario, keyword_init: true)
  MAX_LENGTH = 100
  NAME_LENGTH = 80

  def self.call(story:, actor:, name:, given_text:, when_text:, then_text:)
    errors = errors(name, given_text, when_text, then_text)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    scenario = nil
    DB.transaction do
      position = (Scenario.where(story_id: story.id).max(:position) || 0) + 1000
      scenario = Scenario.create(story_id: story.id, name: name, given_text: given_text, when_text: when_text,
        then_text: then_text, position: position)
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'scenario_added')
    end
    Result.new(success?: true, errors: [], scenario: scenario)
  end

  # What is wrong with a scenario's name and parts, if anything.
  def self.errors(name, given_text, when_text, then_text)
    parts = { 'Name' => [name, NAME_LENGTH], 'Given' => [given_text, MAX_LENGTH], 'When' => [when_text, MAX_LENGTH],
              'Then' => [then_text, MAX_LENGTH] }
    parts.flat_map { |part, (text, limit)|
      [("#{part} is required" if text.to_s.empty?),
       ("#{part} must be #{limit} characters or fewer" if text.to_s.length > limit)]
    }.compact
  end
end
