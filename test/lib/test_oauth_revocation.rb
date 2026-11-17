# frozen_string_literal: true

require 'base64'
require 'digest'
require 'date'
require_relative '../model_spec_helper'
require_relative '../../lib/oauth_revocation'
require_relative '../../lib/oauth_tokens'
require_relative '../../lib/sign_in_grant'
require_relative '../../lib/create_personal_token'

describe OauthRevocation do
  cover 'OauthRevocation*'

  before do
    @now = Time.now
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @team = Team.create(name: 'Payments')
    TeamMembership.create(team_id: @team.id, person_id: @alice.id, working: true)
    @mine = signed_in_tokens
    @other = signed_in_tokens
  end

  def client
    'https://claude.ai/oauth/claude-code-client-metadata'
  end

  def signed_in_tokens
    verifier = 'mainline-test-verifier-0123456789-abcdefghijklmnop'
    request = OauthRequest::Request.new(client_id: client, redirect_uri: 'http://localhost:4000/callback', state: nil,
      challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      resource: "#{ENV.fetch('BASE_URL')}/mcp", name: 'Claude Code', recognised: true)
    code = SignInGrant.call(person: @alice, request: request, team_ids: [@team.id], now: @now).code
    OauthTokens.call({ 'grant_type' => 'authorization_code', 'code' => code, 'code_verifier' => verifier,
                       'client_id' => client, 'redirect_uri' => request.redirect_uri, 'resource' => request.resource },
      now: @now).tokens
  end

  def revoke(token, client_id: client)
    OauthRevocation.call({ 'token' => token, 'client_id' => client_id }.compact, now: @now)
  end

  def revoked?(tokens)
    OauthTokens.call({ 'grant_type' => 'refresh_token', 'refresh_token' => tokens[:refresh_token], 'client_id' => client },
      now: @now).error == 'invalid_grant'
  end

  it 'ends the sign-in a refresh token belongs to, and no other' do
    assert_nil revoke(@mine[:refresh_token]).error

    assert revoked?(@mine)
    refute revoked?(@other)
  end

  it 'ends the sign-in an access token belongs to, and no other' do
    assert_nil revoke(@mine[:access_token]).error

    assert revoked?(@mine)
    refute revoked?(@other)
  end

  it 'answers a token it does not know without an error, and ends nothing' do
    assert_nil revoke('not-a-token').error

    refute revoked?(@mine)
  end

  it 'refuses a token sent by another app, and ends nothing' do
    assert_equal 'unauthorized_client', revoke(@mine[:refresh_token], client_id: 'https://chatgpt.com/oauth/client.json').error

    refute revoked?(@mine)
  end

  it 'leaves personal tokens to the Coding agents page' do
    token = CreatePersonalToken.call(person: @alice, name: 'runner', team_ids: [@team.id], expires_on: Date.today + 30).token

    assert_equal 'unauthorized_client', revoke(token).error
    assert_nil OauthGrant.first(client_id: nil).revoked_at
  end

  it 'keeps the time a sign-in was first revoked' do
    revoke(@mine[:refresh_token])
    grant_id = DB[:oauth_refresh_tokens].first(token_hash: Digest::SHA256.hexdigest(@mine[:refresh_token]))[:grant_id]

    OauthRevocation.call({ 'token' => @mine[:access_token], 'client_id' => client }, now: @now + 60)

    assert_in_delta @now.to_f, OauthGrant[grant_id].revoked_at.to_f, 1
  end

  it 'needs a token and the app' do
    [['', client], [nil, client], [@mine[:refresh_token], ''], [@mine[:refresh_token], nil],
     [[@mine[:refresh_token]], client], [@mine[:refresh_token], [client]]].each do |token, client_id|
      assert_equal 'invalid_request', OauthRevocation.call({ 'token' => token, 'client_id' => client_id }.compact, now: @now).error
    end
  end
end
