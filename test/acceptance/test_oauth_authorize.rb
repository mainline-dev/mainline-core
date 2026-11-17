# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/oauth_dsl'

# A coding agent signs in by sending its person's browser to
# /oauth/authorize. The person sees which app is asking, ticks the teams it may
# read, and approves or denies; either way the browser goes back to the app,
# with a code or a refusal, and with Mainline named as the issuer. An app that
# cannot be identified, or asks to send the person somewhere it does not list,
# gets a page and is sent nothing.
describe 'Signing in a coding agent' do
  include MainlineDSL
  include OauthDsl

  before do
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    @mobile = another_team('Mobile')
    add_member(@alice, @mobile)
    client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback', 'http://127.0.0.1/callback'])
  end

  after { forget_client_documents }

  it 'asks the person to let a recognised app read the teams they tick, each ticked to start' do
    start_sign_in

    consent = consent_shown

    assert_equal ['Claude Code', true, false], [consent[:client], consent[:recognised], consent[:warning]]
    assert_equal({ 'Mobile' => true, 'Payments' => true }, consent[:teams])
  end

  it 'names an app it does not recognise by its site, never by the name it gives itself, with a warning' do
    client_publishes('https://agent.example/client.json', name: 'Claude', redirect_uris: ['https://agent.example/callback'])

    start_sign_in(client_id: 'https://agent.example/client.json', redirect_uri: 'https://agent.example/callback')

    consent = consent_shown

    assert_equal ['agent.example', false, true], [consent[:client], consent[:recognised], consent[:warning]]
    assert_equal 'agent.example', consent[:sends_back_to]
  end

  it 'sends the person back with a code once they approve, naming Mainline as the issuer' do
    start_sign_in(state: 'abc123')

    approve_sign_in

    back = sent_back

    assert_equal 'http://localhost:53682/callback', back[:to]
    refute_nil back['code']
    assert_equal [ENV.fetch('BASE_URL'), 'abc123'], [back['iss'], back['state']]
  end

  it 'gives the sign-in only the teams left ticked' do
    start_sign_in

    approve_sign_in(teams: [@mobile])

    assert_equal ['Mobile'], teams_given_by_last_sign_in
  end

  it 'needs at least one team ticked' do
    start_sign_in

    approve_sign_in(teams: [])

    assert_nil sent_back
    assert_nil teams_given_by_last_sign_in
  end

  it 'offers only the teams whose maps the person can open' do
    ops = another_team('Ops')
    add_member(@alice, ops, working: false)
    start_sign_in

    approve_sign_in(teams: [ops])

    assert_equal({ 'Mobile' => true, 'Payments' => true }, consent_shown[:teams])
    assert_nil teams_given_by_last_sign_in
  end

  it 'sends the person back with a refusal when they deny' do
    start_sign_in(state: 'abc123')

    deny_sign_in

    assert_equal ['access_denied', 'abc123', ENV.fetch('BASE_URL')], sent_back.values_at('error', 'state', 'iss')
    assert_nil teams_given_by_last_sign_in
  end

  it 'sends someone signed out to sign in, then back to the app asking' do
    choose_password('correct horse battery')
    sign_out

    start_sign_in

    refute_nil signed_in_first
    sign_in_with_password(email: @alice.email, password: 'correct horse battery')
    follow_on

    assert_equal 'Claude Code', consent_shown[:client]
  end

  it 'shows a page, and sends nothing back, for an app whose document cannot be had' do
    start_sign_in(client_id: 'https://nowhere.example/client.json')

    assert_nil sent_back
    assert_predicate self, :sign_in_refused_on_page?
  end

  it 'shows a page, and sends nothing back, for an app or an address given more than once' do
    start_sign_in(client_id: [OauthDsl::CLAUDE_CODE, OauthDsl::CLAUDE_CODE])

    assert_predicate self, :sign_in_refused_on_page?

    start_sign_in(redirect_uri: ['http://localhost:53682/callback'])

    assert_predicate self, :sign_in_refused_on_page?
  end

  it 'shows a page, and sends nothing back, for an address the app does not list' do
    start_sign_in(redirect_uri: 'https://claude.ai/somewhere-else')

    assert_nil sent_back
    assert_predicate self, :sign_in_refused_on_page?
  end

  it 'sends back a refusal for a request without PKCE, or with a plain challenge' do
    start_sign_in(challenge: nil)

    assert_equal 'invalid_request', sent_back['error']

    start_sign_in(method: 'plain')

    assert_equal 'invalid_request', sent_back['error']
  end

  it 'sends back a refusal for a request for anything but its MCP endpoint, or anything but a code' do
    start_sign_in(resource: 'https://elsewhere.example/mcp')

    assert_equal 'invalid_target', sent_back['error']

    start_sign_in(response_type: 'token')

    assert_equal ['unsupported_response_type', ENV.fetch('BASE_URL')], sent_back.values_at('error', 'iss')
  end

  it 'refuses an approval sent without the page\'s security token' do
    start_sign_in

    assert(refused_without_security_token? { approve_sign_in })
  end
end
