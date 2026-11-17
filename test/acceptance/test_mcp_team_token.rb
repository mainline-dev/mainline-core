# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

# The old address, /mcp/<team id>, reached with the one token a team's
# account holder makes on the team's MCP page. Personal tokens at /mcp
# replace it, and it goes with team tokens.
describe 'A team token at /mcp/<team id>' do
  include MainlineDSL
  include McpDSL

  before do
    MCP_RATE_LIMITER.reset
    setup_team
    @alice = add_person(name: 'Alice')
    @team.update(creator_id: @alice.id)
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story = create_story('Show results', under_task: task)
    @story.update(description: 'Display search results')
    create_scenario(@story, name: 'Search shows matching results', given_text: 'a query', when_text: 'I search',
      then_text: 'I see results')
    @story.refresh
  end

  it 'rejects unauthenticated request' do
    generate_mcp_token

    post(
      "/mcp/#{@team.id}",
      JSON.generate({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => 'Bearer wrong-token'
    )

    assert_equal 401, last_response.status
  end

  it 'shows the endpoint under the base url of this install' do
    generate_mcp_token

    visit_mcp_token_settings

    assert_page_includes "#{ENV.fetch('BASE_URL')}/mcp/#{@team.id}"
  end

  it 'points an unknown team at the signup page of this install' do
    response = team_token_initialize(team_id: '00000000-0000-0000-0000-000000000000', token: 'none')

    assert_equal 404, response.status
    assert_includes response.body, "#{ENV.fetch('BASE_URL')}/signup"
  end

  it 'rejects request when no MCP token configured' do
    post(
      "/mcp/#{@team.id}",
      JSON.generate({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => 'Bearer anything'
    )

    assert_equal 401, last_response.status
  end

  it 'blocks MCP access when the team is suspended' do
    generate_mcp_token
    suspend_team

    resp = team_token_call_tool('list_maps')

    assert_equal 403, resp.status
    assert_includes resp.body, 'team inactive'
  end

  it "get_story says nothing of whether the agent's person is on the story, since a team token has no person" do
    generate_mcp_token
    team_token_initialize

    text, = mcp_tool_text(team_token_call_tool('get_story', arguments: { 'story_id' => @story.id }))

    refute JSON.parse(text).key?('assigned_to_you')
  end

  it 'only the account holder can rotate the MCP token' do
    bob = add_person(name: 'Bob')
    login_as(bob)

    driver.submit_generate_mcp_token(@team)
    @team.refresh

    assert_nil @team.mcp_token
  end

  # The account holder may pay for and run a team without working on it. The
  # token is theirs alone to create, so its page opens for them either way.
  describe 'an account holder who is not working on the team' do
    before do
      @holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: @holder.id, working: false)
      @team.update(creator_id: @holder.id)
      login_as(@holder)
    end

    it 'opens the MCP page' do
      assert_equal 200, visit_mcp_token_settings.status
    end

    it 'creates the token, and an agent connects with it' do
      generate_mcp_token

      refute_nil @team.mcp_token
      assert_equal 200, team_token_initialize.status
    end
  end

  it 'still sends a member who is not working, and is not the account holder, back to the team page' do
    watcher = Person.create(name: 'Watcher', email: 'watcher@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: watcher.id, working: false)
    login_as(watcher)

    visited = visit_mcp_token_settings

    assert_equal 302, visited.status
    assert_equal "/teams/#{@team.id}", URI(visited.headers['Location']).path
  end

  it 'rotating the MCP token records an event' do
    generate_mcp_token

    event = Event.where(entity_id: @team.id, action: 'mcp_token_rotated').first

    refute_nil event
  end

  it 'authenticates from cache on second request' do
    generate_mcp_token
    resp1 = team_token_initialize

    assert_equal 200, resp1.status

    resp2 = team_token_call_tool('list_maps')

    assert_equal 200, resp2.status
  end

  it 'rejects cached token after team regenerates MCP token' do
    generate_mcp_token
    old_token = @mcp_token
    resp = team_token_initialize

    assert_equal 200, resp.status

    generate_mcp_token
    resp = team_token_initialize(token: old_token)

    assert_equal 401, resp.status
  end

  it 'rate limits failed auth attempts' do
    generate_mcp_token

    11.times do
      post(
        "/mcp/#{@team.id}",
        JSON.generate({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
        'CONTENT_TYPE'       => 'application/json',
        'HTTP_ACCEPT'        => 'application/json',
        'HTTP_AUTHORIZATION' => 'Bearer wrong-token'
      )
    end

    assert_equal 429, last_response.status
  end

  it 'returns helpful error for placeholder team ID' do
    post(
      '/mcp/YOUR_TEAM_ID',
      JSON.generate({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
      'CONTENT_TYPE' => 'application/json',
      'HTTP_ACCEPT'  => 'application/json'
    )

    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)

    assert_includes body['error'], 'team ID'
  end

  it 'returns helpful error for URL-encoded placeholder' do
    post(
      '/mcp/%7Bteam_id%7D',
      JSON.generate({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
      'CONTENT_TYPE' => 'application/json',
      'HTTP_ACCEPT'  => 'application/json'
    )

    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)

    assert_includes body['error'], 'team ID'
  end
end
