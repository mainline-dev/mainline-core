# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

# A personal token is sent to /mcp, the one address every coding agent uses.
# It reads the maps and stories of the teams its person ticked, and no others:
# a story on one of their own teams they left unticked gets a refusal that
# says so, and a story anywhere else gets the same answer as one that does not
# exist, so a refusal never confirms another team's story is there.
describe 'A personal token at /mcp' do
  include MainlineDSL
  include McpDSL

  before do
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    @card = story_on(@team, 'Shoppers can pay by card')
    @mobile = another_team('Mobile')
    add_member(@alice, @mobile)
    @app = story_on(@mobile, 'Shoppers can pay in the app')
  end

  after { back_to_today }

  def story_on(team, title)
    on_team(team) do
      create_map(name: "#{team.name} map")
      activity = create_activity("#{team.name} checkout", for_personas: [create_persona('Shopper')])
      task = create_task('Pay', under_activity: activity)
      create_story(title, under_task: task)
    end
  end

  def token_for(*teams)
    create_personal_token(name: 'build runner', teams: teams, expires_on: Date.today + 30)
  end

  def map_names(token, **arguments)
    mcp_json(call_mcp('list_maps', token: token, arguments: arguments)).map { |map| map['name'] }
  end

  def story_title(token, story)
    response = call_mcp('get_story', token: token, arguments: { story_id: story.id })
    text, refused = mcp_tool_text(response)
    refused ? nil : JSON.parse(text)['title']
  end

  def answer_for(token, story_id)
    mcp_tool_text(call_mcp('get_story', token: token, arguments: { story_id: story_id }))
  end

  def not_there_answer(token)
    answer_for(token, '00000000-0000-4000-8000-000000000000')
  end

  def refused_as_invalid?(response)
    response.status == 401 && response.headers['WWW-Authenticate'].include?('error="invalid_token"')
  end

  it 'connects' do
    assert_equal 200, connect_mcp(token: token_for(@team)).status
  end

  it 'lists the maps of every team it was given, each with its team' do
    maps = mcp_json(call_mcp('list_maps', token: token_for(@team, @mobile)))

    assert_equal [['Mobile map', 'Mobile'], ['Payments map', 'Payments']],
      maps.map { |map| [map['name'], map.dig('team', 'name')] }.sort
  end

  it "lists one team's maps when asked for that team" do
    assert_equal ['Mobile map'], map_names(token_for(@team, @mobile), team_id: @mobile.id)
  end

  it 'reads a story, and a map, on any team it was given' do
    token = token_for(@team, @mobile)

    assert_equal 'Shoppers can pay by card', story_title(token, @card)
    assert_equal 'Shoppers can pay in the app', story_title(token, @app)
    _, refused = mcp_tool_text(call_mcp('get_map', token: token, arguments: { map_id: @map.id }))

    refute refused
  end

  it 'finds a story on any of its teams by the 8-character ID on its card' do
    response = call_mcp('get_story', token: token_for(@team, @mobile), arguments: { story_id: @app.id[0, 8].upcase })

    assert_equal 'Shoppers can pay in the app', mcp_json(response)['title']
  end

  it 'says so when a story is on one of the person\'s teams it was not given' do
    token = token_for(@team)

    text, refused = answer_for(token, @app.id)

    assert refused
    assert_includes text, 'Mobile'
    refute_equal not_there_answer(token), [text, refused]
  end

  it "says so when asked for the maps of one of the person's teams it was not given" do
    text, refused = mcp_tool_text(call_mcp('list_maps', token: token_for(@team), arguments: { team_id: @mobile.id }))

    assert refused
    assert_includes text, 'Mobile'
  end

  it 'answers for a story on a team the person is not on as for a story that does not exist' do
    token = token_for(@team)
    leaves_team(@alice, @mobile)

    assert_equal not_there_answer(token), answer_for(token, @app.id)
    assert_equal not_there_answer(token), answer_for(token, @app.id[0, 8])
  end

  it 'loses a team the person leaves, and keeps the others' do
    token = token_for(@team, @mobile)

    leaves_team(@alice, @mobile)

    assert_equal ['Payments map'], map_names(token)
    assert_nil story_title(token, @app)
  end

  it 'refuses the maps and stories of a suspended team, saying so' do
    token = token_for(@team, @mobile)

    suspend_team(@mobile)

    text, refused = answer_for(token, @app.id)

    assert refused
    assert_includes text, 'Mobile'
    assert_equal ['Payments map'], map_names(token)
  end

  it 'is turned away when every team it was given is suspended' do
    token = token_for(@mobile)

    suspend_team(@mobile)

    assert_equal 403, connect_mcp(token: token).status
  end

  it 'is turned away when the person is on none of its teams any more' do
    token = token_for(@mobile)

    leaves_team(@alice, @mobile)

    assert_equal 403, connect_mcp(token: token).status
  end

  it 'is refused once it has expired' do
    token = token_for(@team)

    days_pass(31)

    assert refused_as_invalid?(connect_mcp(token: token))
  end

  it 'is refused once it is revoked' do
    token = token_for(@team)

    revoke_personal_token('build runner')

    assert refused_as_invalid?(connect_mcp(token: token))
  end

  it 'refuses a token nobody made, however well it is formed' do
    assert refused_as_invalid?(connect_mcp(token: personal_token_nobody_made))
    assert refused_as_invalid?(connect_mcp(token: 'not-a-token'))
  end

  it 'shows on the Coding agents page when it was last used' do
    token = token_for(@team)

    call_mcp('list_maps', token: token)

    refute_nil personal_tokens_listed.first[:last_used]
  end

  it "records a read as its person's, through a personal token" do
    call_mcp('get_story', token: token_for(@mobile), arguments: { story_id: @app.id })

    visit_story_history(@app)

    assert(story_history.any? { |entry| entry.include?('Alice') && entry.include?('personal token') })
  end

  it 'tells the agent whether its person is on the story' do
    token = token_for(@team, @mobile)
    assign_person(@app, person: @alice)

    on = mcp_json(call_mcp('get_story', token: token, arguments: { story_id: @app.id }))
    off = mcp_json(call_mcp('get_story', token: token, arguments: { story_id: @card.id }))

    assert_equal [true, false], [on['assigned_to_you'], off['assigned_to_you']]
  end

  it 'gives the import format with the activities and steps of its one team' do
    text, = mcp_tool_text(call_mcp('get_import_format', token: token_for(@mobile)))

    assert_includes text, 'Mobile checkout'
  end

  it 'gives the import format alone, naming the teams it can be asked for, when it reads several' do
    text, refused = mcp_tool_text(call_mcp('get_import_format', token: token_for(@team, @mobile)))

    refute refused
    refute_includes text, 'checkout'
    assert_includes text, @mobile.id
    assert_includes text, @team.id
  end

  it 'gives the activities and steps of the team asked for' do
    token = token_for(@team, @mobile)

    text, = mcp_tool_text(call_mcp('get_import_format', token: token, arguments: { team_id: @mobile.id }))

    assert_includes text, 'Mobile checkout'
    refute_includes text, 'Payments checkout'
  end

  it "says so when asked for the import format of one of the person's teams it was not given" do
    text, refused = mcp_tool_text(call_mcp('get_import_format', token: token_for(@team), arguments: { team_id: @mobile.id }))

    assert refused
    assert_includes text, 'Mobile'
  end
end
