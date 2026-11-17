# frozen_string_literal: true

require_relative 'record_event'
require_relative 'release_block'
require_relative 'split_candidate'
require_relative 'two_person_rule'
require_relative 'urgent_story'

# Releases an active story that has been deployed: everyone on it is
# unassigned, it is released, and the release is recorded with how its
# scenarios stood. Its scenarios hold it back until they are done, and a story
# one person worked on waits for its walkthrough, except that an urgent story
# goes first and is walked through afterwards.
module ReleaseStory
  Result = Struct.new(:success?, :error, :reason, keyword_init: true)
  NOT_ACTIVE = 'Only active stories can be released'
  NOT_DEPLOYED = 'Story must be deployed at least once before release'

  def self.call(story:, team:, actor:, reason:, now:)
    error, why = refusal(story, team, reason)
    return Result.new(success?: false, error: error, reason: why) if error

    released = { status: 'released' }.merge(ReleaseBlock.recorded(story, reason: reason))
    released[TwoPersonRule::BEFORE_WALKTHROUGH] = true if TwoPersonRule.blocks_release?(story, team)
    DB.transaction do
      StoryAssignment.where(story_id: story.id).each do |assignment|
        assignment.destroy
        RecordEvent.call(actor_id: actor.id, entity: story, action: 'person_unassigned',
          before_state: { person_id: assignment.person_id, reason: 'released' })
      end
      story.update(status: 'released', released_at: now)
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'released', after_state: released)
      SplitCandidate.invalidate_threshold!(team.id)
    end
    Result.new(success?: true)
  end

  # Why the story can't go yet, and the reason's short name, or nil.
  def self.refusal(story, team, reason)
    return [NOT_ACTIVE] unless story.status == 'active'
    return [NOT_DEPLOYED] unless story.deploy_count.positive?

    held = ReleaseBlock.refusal(story, reason: reason)
    return [held_back(story, held), held] if held

    [TwoPersonRule::REFUSAL, TwoPersonRule::REASON] if TwoPersonRule.blocks_release?(story, team) && !UrgentStory.urgent?(story)
  end

  # What a story's scenarios holding it back says. A scenario not done is
  # done, split out or deleted first.
  def self.held_back(story, held)
    return ReleaseBlock::REFUSALS.fetch(held) unless held == ReleaseBlock::UNVERIFIED

    undone = Scenario.where(story_id: story.id, done_at: nil).count
    "#{undone} #{undone == 1 ? 'scenario' : 'scenarios'} not yet verified. " \
      'Mark them done, split them out or delete them before releasing.'
  end
  private_class_method :refusal, :held_back
end
