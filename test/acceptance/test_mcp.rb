# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

describe 'MCP server' do
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

  it 'accepts clients connecting through the app host' do
    generate_mcp_token

    response = connect_mcp_client(host: ENV.fetch('MAINLINE_HOST'), token: @mcp_token)

    assert_equal 200, response.status
  end

  it 'refuses clients connecting through another host' do
    generate_mcp_token

    response = connect_mcp_client(host: 'evil.example.com', token: @mcp_token)

    assert_equal 403, response.status
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
    response = mcp_initialize(team_id: '00000000-0000-0000-0000-000000000000', token: 'none')

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

    resp = mcp_call_tool('list_maps')

    assert_equal 403, resp.status
    assert_includes resp.body, 'team inactive'
  end

  it 'initializes MCP session' do
    generate_mcp_token
    resp = mcp_initialize

    assert_equal 200, resp.status

    body = JSON.parse(resp.body)

    assert_equal '2.0', body['jsonrpc']
    refute_nil body.dig('result', 'serverInfo', 'name')
  end

  it 'list_maps returns team maps' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('list_maps')

    assert_equal 200, resp.status

    body = JSON.parse(resp.body)
    content = body.dig('result', 'content')

    refute_nil content
    text = content.find { |c| c['type'] == 'text' }
    maps = JSON.parse(text['text'])

    assert_equal 1, maps.length
    assert_equal 'Product Map', maps[0]['name']
    assert_equal @map.id, maps[0]['id']
  end

  it 'get_map returns full map hierarchy' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_map', arguments: { 'map_id' => @map.id })

    assert_equal 200, resp.status

    body = JSON.parse(resp.body)
    text = body.dig('result', 'content')&.find { |c| c['type'] == 'text' }
    map_data = JSON.parse(text['text'])

    assert_equal 'Product Map', map_data['name']
    assert_equal 1, map_data['activities'].length
    assert_equal 'Browse', map_data['activities'][0]['name']
    assert_equal 1, map_data['activities'][0]['steps'].length
    assert_equal 'Search', map_data['activities'][0]['steps'][0]['name']
    assert_equal 1, map_data['activities'][0]['steps'][0]['stories'].length
    assert_equal 'Show results', map_data['activities'][0]['steps'][0]['stories'][0]['title']
  end

  it 'get_story returns story detail with scenarios' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })

    assert_equal 200, resp.status

    body = JSON.parse(resp.body)
    text = body.dig('result', 'content')&.find { |c| c['type'] == 'text' }
    story_data = JSON.parse(text['text'])

    assert_equal 'Show results', story_data['title']
    assert_equal 'Display search results', story_data['description']
    assert_equal 1, story_data['scenarios'].length
    assert_equal 'a query', story_data['scenarios'][0]['given']
    assert_equal 'I search', story_data['scenarios'][0]['when']
    assert_equal 'I see results', story_data['scenarios'][0]['then']
    assert_equal 'Search shows matching results', story_data['scenarios'][0]['name']
  end

  it 'get_feature_file returns the scenarios as a feature file and marks the story as agent-read' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id })
    text = JSON.parse(resp.body).dig('result', 'content')&.find { |c| c['type'] == 'text' }

    assert_includes text['text'], "@story-#{@story.id}"
    assert_includes text['text'], 'Scenario: Search shows matching results'
    assert_equal(1, BypassRLS.call { Event.where(entity_id: @story.id, action: 'agent_read').count })
  end

  it 'get_feature_file adds step stubs in the language asked for' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id, 'language' => 'typescript' })
    texts = JSON.parse(resp.body).dig('result', 'content').map { |c| c['text'] }

    assert_includes texts[0], 'Feature: Show results'
    assert_includes texts[1], "Given('a query', function () {"
  end

  it "get_import_format returns the instructions and schema for writing an import file, naming the team's steps" do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_import_format')
    text = JSON.parse(resp.body).dig('result', 'content').first['text']

    assert_includes text, 'https://mainline.dev/schemas/import-1.json'
    assert_includes text, 'Browse: Search'
  end

  it 'get_import_format changes nothing: no story is marked as read by an agent' do
    generate_mcp_token
    mcp_initialize

    mcp_call_tool('get_import_format')

    assert_equal(0, BypassRLS.call { Event.where(team_id: @team.id, action: 'agent_read').count })
    refute @story.refresh.agent_assisted
  end

  it 'get_feature_file refuses a language it does not know' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id, 'language' => 'cobol' })

    assert JSON.parse(resp.body).dig('result', 'isError')
  end

  it "get_feature_file refuses another team's story" do
    other = BypassRLS.call {
      team = Team.create(name: 'Other')
      map = Map.create(team_id: team.id, name: 'Theirs', position: 1000)
      activity = Activity.create(map_id: map.id, team_id: team.id, name: 'A', position: 1000)
      task = Task.create(activity_id: activity.id, map_id: map.id, team_id: team.id, name: 'T', position: 1000)
      creator = Person.create(name: 'Them', email: 'them@other.test')
      Story.create(task_id: task.id, map_id: map.id, team_id: team.id, title: 'Theirs', position: 1000,
        created_by_id: creator.id)
    }
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => other.id })

    assert JSON.parse(resp.body).dig('result', 'isError')
  end

  it 'get_story names a scenario written before names by its Then line' do
    Scenario.create(story_id: @story.id, given_text: 'no query', when_text: 'I search', then_text: 'I see a prompt',
      position: 2000)
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    text = JSON.parse(resp.body).dig('result', 'content')&.find { |c| c['type'] == 'text' }

    names = JSON.parse(text['text'])['scenarios'].map { |sc| sc['name'] }

    assert_equal ['Search shows matching results', 'I see a prompt'], names
  end

  it 'get_story does not expose deploy webhook URL' do
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    body = JSON.parse(resp.body)
    text = body.dig('result', 'content')&.find { |c| c['type'] == 'text' }
    story_data = JSON.parse(text['text'])

    refute story_data.key?('deploy_webhook_url')
    assert_equal @story.id[0, 8].upcase, story_data['short_id']
  end

  it 'marks story as agent_assisted when accessed via get_story' do
    generate_mcp_token
    mcp_initialize

    refute @story.agent_assisted

    mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })

    @story.refresh

    assert @story.agent_assisted
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
      assert_equal 200, connect_mcp_client(host: ENV.fetch('MAINLINE_HOST'), token: @mcp_token).status
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

  it 'get_story scenarios carry done state' do
    scenario = Scenario.where(story_id: @story.id).first
    mark_scenario_done(@story, scenario)
    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    text = JSON.parse(resp.body).dig('result', 'content', 0, 'text')
    story_data = JSON.parse(text)

    done_flags = story_data['scenarios'].map { |sc| sc['done'] }

    assert_equal [true], done_flags
  end

  it 'exposes only read tools - no scenario or story mutation' do
    generate_mcp_token
    mcp_initialize

    post(
      "/mcp/#{@team.id}",
      JSON.generate({ jsonrpc: '2.0', id: 3, method: 'tools/list' }),
      'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{@mcp_token}", 'HTTP_HOST' => ENV.fetch('MAINLINE_HOST')
    )
    names = JSON.parse(last_response.body).dig('result', 'tools').map { |t| t['name'] }.sort

    assert_empty %w[get_map get_story list_maps] - names
  end

  it 'records an agent_read event for every get_story fetch' do
    generate_mcp_token
    mcp_initialize

    mcp_call_tool('get_story', arguments: { 'story_id' => @story.id }, user_agent: 'claude-code/2.0')
    mcp_call_tool('get_story', arguments: { 'story_id' => @story.id }, user_agent: 'other-agent/1.1')

    events = Event.where(entity_id: @story.id, action: 'agent_read').order(:event_no).all

    assert_equal 2, events.length
    assert_equal 'claude-code/2.0', events[0].after_state['user_agent']
    assert_equal 'other-agent/1.1', events[1].after_state['user_agent']
    assert_equal 'system', events[0].actor.kind
  end

  it 'an agent read records who was on the story at the time' do
    bob = add_person(name: 'Bob')
    assign_person(@story, person: bob)
    generate_mcp_token
    mcp_initialize

    mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })

    event = assert_event_recorded(entity: @story, action: 'agent_read')

    assert_equal [bob.id], event.after_state['person_ids']
  end

  it 'rejects get_map for map on different team' do
    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)
    other_map = Map.create(team_id: other_team.id, name: 'Secret Map', position: 1000)

    generate_mcp_token
    mcp_initialize

    resp = mcp_call_tool('get_map', arguments: { 'map_id' => other_map.id })

    body = JSON.parse(resp.body)

    assert body.dig('result', 'isError')
  end

  it 'authenticates from cache on second request' do
    generate_mcp_token
    resp1 = mcp_initialize

    assert_equal 200, resp1.status

    resp2 = mcp_call_tool('list_maps')

    assert_equal 200, resp2.status
  end

  it 'rejects cached token after team regenerates MCP token' do
    generate_mcp_token
    old_token = @mcp_token
    resp = mcp_initialize

    assert_equal 200, resp.status

    generate_mcp_token
    resp = mcp_initialize(token: old_token)

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
