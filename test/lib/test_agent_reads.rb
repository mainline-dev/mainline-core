# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/agent_reads'

describe AgentReads do
  cover 'AgentReads*'

  before do
    @team = Team.create(name: 'Reads Team')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@reads.co')
    @map = Map.create(team_id: @team.id, name: 'Product', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    @task = Task.create(map_id: @map.id, team_id: @team.id, activity_id: activity.id, name: 'Search', position: 1000)
    @read = story('Read', 1000)
    @unread = story('Unread', 2000)
  end

  def story(title, position)
    Story.create(map_id: @map.id, team_id: @team.id, task_id: @task.id, title: title, position: position,
      created_by_id: @person.id)
  end

  def record(action, story)
    RecordEvent.call(actor_id: @team.mcp_actor_id, entity: story, action: action)
  end

  it 'finds the stories a coding agent has read among those asked about' do
    record('agent_read', @read)

    assert_equal Set[@read.id], AgentReads.story_ids([@read.id, @unread.id])
  end

  it 'finds nothing for a story it was not asked about' do
    record('agent_read', @read)

    assert_empty AgentReads.story_ids([@unread.id])
  end

  it 'counts only reads, not other events on the story' do
    record('deployed', @read)

    assert_empty AgentReads.story_ids([@read.id])
  end

  it "finds the reads among a map's stories" do
    record('agent_read', @read)

    assert_equal Set[@read.id], AgentReads.story_ids(Story.where(map_id: @map.id).select(:id))
  end

  it 'says whether a coding agent has read one story' do
    record('agent_read', @read)

    assert AgentReads.read?(@read.id)
    refute AgentReads.read?(@unread.id)
  end
end
