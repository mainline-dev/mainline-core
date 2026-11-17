# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/oauth_dsl'
require_relative '../dsl/mcp_dsl'

# A coding agent's app that signs in through the browser is listed on its
# person's Coding agents page while its sign-in works: the app, its teams, and
# when it was signed in and last used. Revoking it there stops the app at once.
# A sign-in left unused until its refresh token runs out is no longer listed.
describe 'Apps signed in, on the Coding agents page' do
  include MainlineDSL
  include OauthDsl
  include McpDSL

  before do
    turn_oauth_on
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback'])
  end

  after do
    forget_client_documents
    back_to_today
  end

  def today
    Time.now.utc.to_date.iso8601
  end

  it 'lists an app once it has signed in, with its teams, and when it signed in and was last used' do
    tokens = sign_in_an_app
    call_mcp('list_maps', token: tokens['access_token'])

    assert_equal [{ app: 'Claude Code', teams: ['Payments'], signed_in: today, last_used: today }], app_sign_ins_listed
  end

  it 'revokes an app from the list, which stops it at once' do
    tokens = sign_in_an_app

    revoke_app_sign_in('Claude Code')

    assert_empty app_sign_ins_listed
    assert_equal 401, connect_mcp(token: tokens['access_token']).status
  end

  it 'no longer lists an app left unused until its sign-in ran out' do
    sign_in_an_app
    days_pass(61)
    login_as(@alice)

    assert_empty app_sign_ins_listed
  end

  it "lists only the person's own sign-ins, and nobody else can revoke one" do
    sign_in_an_app
    theirs = app_sign_in_ids.first
    login_as(add_person(name: 'Bob'))

    assert_empty app_sign_ins_listed

    revoke_personal_token_by_id(theirs)
    login_as(@alice)

    assert_equal(['Claude Code'], app_sign_ins_listed.map { |app| app[:app] })
  end
end
