# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/oauth_dsl'

# A coding agent's app signs itself out by sending /oauth/revoke either of its
# tokens: the whole sign-in ends, so neither token works again. A token
# Mainline does not know is answered the same as one it revoked, as RFC 7009
# asks, and only the app a token was given to may revoke it.
describe 'An app signing itself out' do
  include MainlineDSL
  include OauthDsl

  before do
    turn_oauth_on
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback'])
    start_sign_in
    approve_sign_in
    @tokens = exchange_code(sent_back['code'])
  end

  after { forget_client_documents }

  it 'ends the sign-in when it sends its refresh token' do
    assert_equal 200, revoke_token(@tokens['refresh_token'])[:status]

    assert_equal 'invalid_grant', refresh(@tokens['refresh_token'])['error']
  end

  it 'ends the sign-in when it sends its access token' do
    assert_equal 200, revoke_token(@tokens['access_token'])[:status]

    assert_equal 'invalid_grant', refresh(@tokens['refresh_token'])['error']
  end

  it 'answers a token it does not know as it answers one it revoked, and ends nothing' do
    assert_equal 200, revoke_token('not-a-token')[:status]

    assert_equal 200, refresh(@tokens['refresh_token'])[:status]
  end

  it 'refuses a token sent by another app, and ends nothing' do
    answer = revoke_token(@tokens['refresh_token'], client_id: 'https://chatgpt.com/oauth/client.json')

    assert_equal [400, 'unauthorized_client'], answer.values_at(:status, 'error')
    assert_equal 200, refresh(@tokens['refresh_token'])[:status]
  end

  it 'needs a token and the app' do
    assert_equal 'invalid_request', revoke_token('')['error']
    assert_equal 'invalid_request', revoke_token(@tokens['refresh_token'], client_id: '')['error']
    assert_equal [400, 'invalid_request'], revoke_token([@tokens['refresh_token']]).values_at(:status, 'error')
  end

  it 'is not refused by the check on forms' do
    assert_equal 200, with_csrf_checked { revoke_token(@tokens['refresh_token']) }[:status]
  end
end
