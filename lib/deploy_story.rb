# frozen_string_literal: true

require_relative 'record_event'

# Marks an active story deployed: one more deploy, when it was first and last
# deployed, and an event with the count. Only an active story is deployed.
module DeployStory
  Result = Struct.new(:success?, :error, keyword_init: true)
  NOT_ACTIVE = 'Only active stories can be deployed'

  def self.call(story:, actor:, now:)
    return Result.new(success?: false, error: NOT_ACTIVE) unless story.status == 'active'

    DB.transaction do
      updates = { deploy_count: Sequel.lit('deploy_count + 1'), last_deployed_at: now }
      updates[:first_deployed_at] = now if story.deploy_count.zero?
      DB[:stories].where(id: story.id).update(updates)
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'deployed',
        after_state: { deploy_count: story.deploy_count + 1 })
    end
    Result.new(success?: true)
  end
end
