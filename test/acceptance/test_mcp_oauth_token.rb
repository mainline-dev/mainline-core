# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'
require_relative '../dsl/oauth_dsl'

# An app that has signed in sends its access token to /mcp. It reads the
# teams its person ticked, as that person, through that app, for an hour; the
# app then refreshes it. Once the sign-in is revoked, it reads nothing.
describe "An app's access token at /mcp" do
  include MainlineDSL
  include McpDSL
  include OauthDsl

  before do
    turn_oauth_on
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    @mobile = another_team('Mobile')
    add_member(@alice, @mobile)
    on_team(@mobile) { create_map(name: 'App') }
    create_map(name: 'Checkout')
    task = create_task('Pay', under_activity: create_activity('Check out', for_personas: [create_persona('Shopper')]))
    @story = create_story('Shoppers can pay by card', under_task: task)
    client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback'])
    start_sign_in
    approve_sign_in(teams: [@team])
    @tokens = exchange_code(sent_back['code'])
  end

  after do
    forget_client_documents
    back_to_today
  end

  def map_names(token)
    mcp_json(call_mcp('list_maps', token: token)).map { |map| map['name'] }
  end

  it 'reads the teams its person ticked, and no others' do
    assert_equal ['Checkout'], map_names(@tokens['access_token'])
  end

  it "records a read as its person's, through the app" do
    call_mcp('get_story', token: @tokens['access_token'], arguments: { story_id: @story.id })

    visit_story_history(@story)

    assert(story_history.any? { |entry| entry.include?('Alice') && entry.include?('claude.ai') })
  end

  it 'is refused once its hour is up, while a refreshed one reads' do
    days_pass(1)

    refute_equal 200, connect_mcp(token: @tokens['access_token']).status

    fresh = refresh(@tokens['refresh_token'])

    assert_equal ['Checkout'], map_names(fresh['access_token'])
  end

  it 'is refused once the sign-in is revoked' do
    revoke_token(@tokens['refresh_token'])

    assert_equal 401, connect_mcp(token: @tokens['access_token']).status
  end
end
