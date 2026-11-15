# frozen_string_literal: true

require_relative 'record_event'

# Which stories a coding agent has read, worked out from the read log: every
# MCP read records an agent_read event and changes nothing else, so the AGENT
# chip and the export ask the log rather than the story.
module AgentReads
  ACTION = 'agent_read'

  # The IDs, among the stories given (IDs or a dataset of them), that a coding
  # agent has read.
  def self.story_ids(stories)
    Event.where(entity_type: RecordEvent.entity_type_for(Story), entity_id: stories, action: ACTION)
      .distinct.select_map(:entity_id).to_set
  end

  def self.read?(story_id)
    story_ids(story_id).any?
  end
end
