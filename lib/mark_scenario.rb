# frozen_string_literal: true

require_relative 'record_event'

# Marks a story's scenario done, or not done again, and records the change.
# Marking it as it already is changes nothing, and a released story's
# scenarios stay as they were when it went out.
module MarkScenario
  Result = Struct.new(:success?, keyword_init: true)

  def self.done(story:, scenario:, actor:, now:)
    mark(story, scenario, actor, done_at: now, action: 'scenario_done', already: !scenario.done_at.nil?)
  end

  def self.undone(story:, scenario:, actor:)
    mark(story, scenario, actor, done_at: nil, action: 'scenario_undone', already: scenario.done_at.nil?)
  end

  def self.mark(story, scenario, actor, done_at:, action:, already:)
    return Result.new(success?: false) if already || story.status == 'released'

    DB.transaction do
      scenario.update(done_at: done_at)
      RecordEvent.call(actor_id: actor.id, entity: story, action: action)
    end
    Result.new(success?: true)
  end
  private_class_method :mark
end
