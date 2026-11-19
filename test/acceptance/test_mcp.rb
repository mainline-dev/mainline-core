# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

describe 'MCP server' do
  include MainlineDSL
  include McpDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @team.update(creator_id: @alice.id)
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
    @story = create_story('Show results', under_task: @task)
    @story.update(description: 'Display search results')
    create_scenario(@story, name: 'Search shows matching results', given_text: 'a query', when_text: 'I search',
      then_text: 'I see results')
    @story.refresh
  end

  it 'accepts clients connecting through the app host' do
    connect_coding_agent

    response = connect_mcp_client(host: ENV.fetch('MAINLINE_HOST'), token: @mcp_token)

    assert_equal 200, response.status
  end

  it 'refuses clients connecting through another host' do
    connect_coding_agent

    response = connect_mcp_client(host: 'evil.example.com', token: @mcp_token)

    assert_equal 403, response.status
  end

  it 'has no address for one team alone, and no team token page' do
    connect_coding_agent

    assert(not_there? { ask_the_old_team_address })
    assert(not_there? { visit_the_old_team_token_page })
  end

  it 'offers the 2026-07-28 protocol to a client that asks which versions it speaks' do
    connect_coding_agent

    assert_includes mcp_versions_offered, '2026-07-28'
  end

  it 'lists its tools for a client on the 2026-07-28 protocol, which opens no session first' do
    connect_coding_agent

    assert_includes mcp_tools_listed_on('2026-07-28'), 'list_maps'
  end

  it 'promises a client on the 2026-07-28 protocol no change notifications, since it cannot send them' do
    connect_coding_agent

    assert(mcp_capabilities_offered.values.none? { |ability| ability.key?('listChanged') })
  end

  it 'answers a request to listen for changes with a refusal, never an empty stream' do
    connect_coding_agent

    refute_predicate self, :mcp_listen_opens_a_stream?
  end

  it 'initializes MCP session' do
    connect_coding_agent
    resp = mcp_initialize

    assert_equal 200, resp.status

    body = JSON.parse(resp.body)

    assert_equal '2.0', body['jsonrpc']
    refute_nil body.dig('result', 'serverInfo', 'name')
  end

  it 'list_maps returns team maps' do
    connect_coding_agent
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
    connect_coding_agent
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
    connect_coding_agent
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
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id })
    text = JSON.parse(resp.body).dig('result', 'content')&.find { |c| c['type'] == 'text' }

    assert_includes text['text'], "@story-#{@story.id}"
    assert_includes text['text'], 'Scenario: Search shows matching results'
    assert_equal(1, BypassRLS.call { Event.where(entity_id: @story.id, action: 'agent_read').count })
  end

  it 'get_feature_file tells an agent a story has no scenarios, with no feature file or stubs' do
    connect_coding_agent
    mcp_initialize
    bare = create_story('No scenarios yet', under_task: @task)

    text, error = mcp_tool_text(mcp_call_tool('get_feature_file', arguments: { 'story_id' => bare.id, 'language' => 'ruby' }))

    assert error
    refute_includes text, 'Feature:'
  end

  it 'get_feature_file adds step stubs in the language asked for' do
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id, 'language' => 'typescript' })
    texts = JSON.parse(resp.body).dig('result', 'content').map { |c| c['text'] }

    assert_includes texts[0], 'Feature: Show results'
    assert_includes texts[1], "Given('a query', function () {"
  end

  it "get_import_format returns the instructions and schema for writing an import file, naming the team's steps" do
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_import_format')
    text = JSON.parse(resp.body).dig('result', 'content').first['text']

    assert_includes text, 'https://mainline.dev/schemas/import-1.json'
    assert_includes text, 'Browse: Search'
  end

  it 'get_import_format changes nothing: no story is marked as read by an agent' do
    connect_coding_agent
    mcp_initialize

    writes = writes_during { mcp_call_tool('get_import_format') }

    assert_empty writes[:events]
    assert_empty writes[:stories]
  end

  it 'get_feature_file refuses a language it does not know' do
    connect_coding_agent
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
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_feature_file', arguments: { 'story_id' => other.id })

    assert JSON.parse(resp.body).dig('result', 'isError')
  end

  it 'get_story names a scenario written before names by its Then line' do
    Scenario.create(story_id: @story.id, given_text: 'no query', when_text: 'I search', then_text: 'I see a prompt',
      position: 2000)
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    text = JSON.parse(resp.body).dig('result', 'content')&.find { |c| c['type'] == 'text' }

    names = JSON.parse(text['text'])['scenarios'].map { |sc| sc['name'] }

    assert_equal ['Search shows matching results', 'I see a prompt'], names
  end

  it 'get_story finds a story by the 8-character ID on its card' do
    connect_coding_agent
    mcp_initialize

    text, error = mcp_tool_text(mcp_call_tool('get_story', arguments: { 'story_id' => @story.id[0, 8].upcase }))

    refute error
    assert_equal 'Show results', JSON.parse(text)['title']
  end

  it 'get_feature_file finds a story by the 8-character ID on its card' do
    connect_coding_agent
    mcp_initialize

    text, error = mcp_tool_text(mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id[0, 8] }))

    refute error
    assert_includes text, "@story-#{@story.id}"
  end

  it 'tells an agent where to find a story ID when none matches' do
    connect_coding_agent
    mcp_initialize

    %w[get_story get_feature_file].product(['00000000', 'YOUR_STORY_ID', '{story_id}']).each do |tool, id|
      text, error = mcp_tool_text(mcp_call_tool(tool, arguments: { 'story_id' => id }))

      assert error, "#{tool} #{id}"
      assert_includes text, 'get_map', "#{tool} #{id}"
    end
  end

  it "finds nothing by the short ID of another team's story" do
    theirs = other_team_story
    connect_coding_agent
    mcp_initialize

    text, error = mcp_tool_text(mcp_call_tool('get_story', arguments: { 'story_id' => theirs.id[0, 8] }))

    assert error
    refute_includes text, 'Their story'
  end

  it 'get_story does not expose deploy webhook URL' do
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    body = JSON.parse(resp.body)
    text = body.dig('result', 'content')&.find { |c| c['type'] == 'text' }
    story_data = JSON.parse(text['text'])

    refute story_data.key?('deploy_webhook_url')
    assert_equal @story.id[0, 8].upcase, story_data['short_id']
  end

  it 'records a read with the coding agent the team already has, creating and changing nothing else' do
    connect_coding_agent
    mcp_initialize

    writes = writes_during { mcp_call_tool('get_story', arguments: { 'story_id' => @story.id }) }

    assert_equal ['agent_read'], writes[:events]
    assert_equal 0, writes[:actors]
    refute writes[:team]
    assert_empty writes[:stories]
  end

  it 'get_feature_file records a read and changes no story' do
    connect_coding_agent
    mcp_initialize

    writes = writes_during { mcp_call_tool('get_feature_file', arguments: { 'story_id' => @story.id }) }

    assert_equal ['agent_read'], writes[:events]
    assert_empty writes[:stories]
  end

  it 'shows AGENT on the card once a coding agent has read the story' do
    connect_coding_agent
    mcp_initialize
    visit_story_card(@story)

    refute_page_includes('data-test-id="agent-chip"')

    mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    visit_story_card(@story)

    assert_page_includes('data-test-id="agent-chip"')
  end

  it 'get_story scenarios carry done state' do
    scenario = Scenario.where(story_id: @story.id).first
    mark_scenario_done(@story, scenario)
    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })
    text = JSON.parse(resp.body).dig('result', 'content', 0, 'text')
    story_data = JSON.parse(text)

    done_flags = story_data['scenarios'].map { |sc| sc['done'] }

    assert_equal [true], done_flags
  end

  it 'exposes only read tools - no scenario or story mutation' do
    connect_coding_agent
    mcp_initialize

    names = mcp_list_tools.map { |t| t['name'] }.sort

    assert_empty %w[get_map get_story list_maps] - names
  end

  it 'gives every tool a title, and says none of them destroys anything or reaches outside Mainline' do
    connect_coding_agent
    mcp_initialize

    mcp_list_tools.each do |tool|
      refute_empty tool['title'].to_s, tool['name']
      assert_equal [false, false], tool['annotations'].values_at('destructiveHint', 'openWorldHint'), tool['name']
    end
  end

  # Reading a story leaves a record in its history, once for every read. A
  # tool that writes anything is not read-only as the directories mean it, so
  # the two that read a story say so, and the rest say they only read.
  it 'says the two tools that read a story leave something behind each time, and that the rest only read' do
    connect_coding_agent
    mcp_initialize

    hints = mcp_list_tools.to_h { |tool| [tool['name'], tool['annotations'].values_at('readOnlyHint', 'idempotentHint')] }
    recording = %w[get_feature_file get_story]

    assert_equal [[false, false]], hints.values_at(*recording).uniq
    assert_equal [[true, true]], hints.except(*recording).values.uniq
  end

  it 'tells a client that every tool needs a sign-in that may read' do
    connect_coding_agent
    mcp_initialize

    sign_in = { 'securitySchemes' => [{ 'type' => 'oauth2', 'scopes' => ['mainline:read'] }] }

    mcp_list_tools.each { |tool| assert_equal sign_in, tool['_meta'], tool['name'] }
  end

  it 'records an agent_read event for every get_story fetch' do
    connect_coding_agent
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
    connect_coding_agent
    mcp_initialize

    mcp_call_tool('get_story', arguments: { 'story_id' => @story.id })

    event = assert_event_recorded(entity: @story, action: 'agent_read')

    assert_equal [bob.id], event.after_state['person_ids']
  end

  it 'rejects get_map for map on different team' do
    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)
    other_map = Map.create(team_id: other_team.id, name: 'Secret Map', position: 1000)

    connect_coding_agent
    mcp_initialize

    resp = mcp_call_tool('get_map', arguments: { 'map_id' => other_map.id })

    body = JSON.parse(resp.body)

    assert body.dig('result', 'isError')
  end
end
