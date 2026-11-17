# frozen_string_literal: true

require_relative 'record_event'

# Removes a scenario from its story and records it. A released story keeps
# its scenarios as they were when it went out.
module RemoveScenario
  Result = Struct.new(:success?, keyword_init: true)

  def self.call(story:, scenario:, actor:)
    return Result.new(success?: false) if story.status == 'released'

    DB.transaction do
      scenario.destroy
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'scenario_removed')
    end
    Result.new(success?: true)
  end
end
