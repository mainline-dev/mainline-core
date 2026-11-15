# frozen_string_literal: true

require_relative '../model_spec_helper'

describe Team do
  it 'gives a new team its own coding agent to record agent reads with' do
    team = Team.create(name: 'Test Team')

    agent = Actor[team.mcp_actor_id]

    assert_equal 'system', agent.kind
    assert_equal 'Coding agent', agent.name
  end

  it 'gives each team a coding agent of its own' do
    first = Team.create(name: 'First')
    second = Team.create(name: 'Second')

    refute_equal first.mcp_actor_id, second.mcp_actor_id
  end
end
