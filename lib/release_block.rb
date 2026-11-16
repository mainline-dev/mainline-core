# frozen_string_literal: true

require_relative 'urgent_story'

# What a story's scenarios say about releasing it. The scenarios say what done
# means, so a story goes out only once it has one and every one is done. A
# story nobody wrote a scenario for can go out with a reason, which the release
# records; an urgent story needs none. A scenario that isn't done is done,
# split out into a story of its own, or deleted: no reason gets past it.
module ReleaseBlock
  NO_SCENARIOS = 'no-scenarios'
  UNVERIFIED = 'unverified-scenarios'
  REASON_NEEDED = 'reason-needed'
  # On the release event of a story released with no scenarios.
  WITHOUT_SCENARIOS = 'without_scenarios'

  REFUSALS = {
    NO_SCENARIOS  => 'This story has no scenarios. Add one and mark it done, or say why it goes out without them.',
    REASON_NEEDED => 'Say why this story goes out without scenarios.'
  }.freeze

  # Why the story can't go out yet, or nil when its scenarios let it.
  def self.of(story)
    blocks([story], urgent: UrgentStory.urgent?(story) ? story : nil)[story.id]
  end

  # The same for many stories at once, by story ID, leaving out those that
  # can go. The team has at most one urgent story.
  def self.blocks(stories, urgent:)
    ids = stories.map(&:id)
    written = Scenario.where(story_id: ids).select_map(:story_id)
    undone = Scenario.where(story_id: ids, done_at: nil).select_map(:story_id)
    stories.each_with_object({}) do |story, held|
      if undone.include?(story.id)
        held[story.id] = UNVERIFIED
      elsif !written.include?(story.id) && story.id != urgent&.id
        held[story.id] = NO_SCENARIOS
      end
    end
  end

  # The refusal for a release asked for, or nil to go ahead. A reason lets a
  # story with no scenarios go, as long as it says something.
  def self.refusal(story, reason:)
    block = of(story)
    return block unless block == NO_SCENARIOS && reason

    REASON_NEEDED if reason.strip.empty?
  end

  # What the release event records of a story that goes out with no scenarios,
  # and why, when someone said.
  def self.recorded(story, reason:)
    return {} if Scenario.where(story_id: story.id).any?

    reason = reason.to_s.strip
    { WITHOUT_SCENARIOS => true }.merge(reason.empty? ? {} : { 'reason' => reason })
  end
end
