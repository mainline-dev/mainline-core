# frozen_string_literal: true

require_relative 'add_scenario'
require_relative 'record_event'

# Saves a scenario's name and parts, held to the same rules as a new one, and
# records the edit only when it changes something, so saving the form as it
# stood is no change. A released story's scenarios stay as they were.
module EditScenario
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(story:, scenario:, actor:, name:, given_text:, when_text:, then_text:)
    return Result.new(success?: false, errors: []) if story.status == 'released'

    errors = AddScenario.errors(name, given_text, when_text, then_text)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      scenario.set(name: name, given_text: given_text, when_text: when_text, then_text: then_text)
      if scenario.modified?
        scenario.save_changes
        RecordEvent.call(actor_id: actor.id, entity: story, action: 'scenario_edited')
      end
    end
    Result.new(success?: true, errors: [])
  end
end
