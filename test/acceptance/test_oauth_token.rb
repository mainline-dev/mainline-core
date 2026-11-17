# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/oauth_dsl'

# Once its person approves, a coding agent's app exchanges the code it was
# sent, with the PKCE verifier only it knows, for an access token that lasts
# an hour and a refresh token that lasts 60 days. A refresh token works once
# and comes back new each time; using a spent one again revokes the sign-in,
# since only someone who stole it would.
describe 'Exchanging a sign-in for tokens' do
  include MainlineDSL
  include OauthDsl

  before do
    turn_oauth_on
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback'])
    start_sign_in
    approve_sign_in
    @code = sent_back['code']
  end

  after do
    forget_client_documents
    back_to_today
  end

  it 'gives an access token for an hour and a refresh token for a code and its verifier' do
    answer = exchange_code(@code)

    assert_equal [200, 'no-store'], answer.values_at(:status, :cache_control)
    assert_equal ['Bearer', 3600, 'mainline:read'], answer.values_at('token_type', 'expires_in', 'scope')
    refute_nil answer['access_token']
    refute_nil answer['refresh_token']
  end

  it 'takes a code once' do
    exchange_code(@code)

    assert_equal [400, 'invalid_grant'], exchange_code(@code).values_at(:status, 'error')
  end

  it 'takes a code for a minute only' do
    days_pass(1)

    assert_equal 'invalid_grant', exchange_code(@code)['error']
  end

  it 'refuses a code with the wrong verifier, or for another app, address or resource, and keeps it for the right one' do
    [{ verifier: "#{OauthDsl::VERIFIER}x" }, { client_id: 'https://chatgpt.com/oauth/client.json' },
     { redirect_uri: 'http://localhost:53682/other' }, { resource: 'https://elsewhere.example/mcp' }].each do |change|
      assert_equal 'invalid_grant', exchange_code(@code, **change)['error'], change.inspect
    end

    assert_equal 200, exchange_code(@code)[:status]
  end

  it 'refreshes with new tokens, and spends the old refresh token' do
    first = exchange_code(@code)

    second = refresh(first['refresh_token'])

    assert_equal 200, second[:status]
    refute_equal first.values_at('access_token', 'refresh_token'), second.values_at('access_token', 'refresh_token')
    assert_equal 'invalid_grant', refresh(first['refresh_token'])['error']
  end

  it 'revokes the sign-in when a spent refresh token is used again' do
    first = exchange_code(@code)
    second = refresh(first['refresh_token'])

    refresh(first['refresh_token'])

    assert_equal 'invalid_grant', refresh(second['refresh_token'])['error']
  end

  it 'refuses a refresh token after 60 days' do
    first = exchange_code(@code)

    days_pass(61)

    assert_equal 'invalid_grant', refresh(first['refresh_token'])['error']
  end

  it 'refuses a refresh token for another app' do
    first = exchange_code(@code)

    assert_equal 'invalid_grant', refresh(first['refresh_token'], client_id: 'https://chatgpt.com/oauth/client.json')['error']
  end

  it 'refuses a refresh token once its person revokes the sign-in' do
    first = exchange_code(@code)

    revoke_last_sign_in

    assert_equal 'invalid_grant', refresh(first['refresh_token'])['error']
  end

  it 'refuses a grant type it does not offer, and a request missing what it needs' do
    assert_equal 'unsupported_grant_type', ask_for_token('grant_type' => 'client_credentials')['error']
    assert_equal 'invalid_request', ask_for_token('grant_type' => 'authorization_code')['error']
    assert_equal 'invalid_request', ask_for_token({})['error']
    assert_equal [400, 'invalid_request'], exchange_code([@code]).values_at(:status, 'error')
  end

  it 'is not refused by the check on forms' do
    assert_equal 200, with_csrf_checked { exchange_code(@code) }[:status]
  end
end
