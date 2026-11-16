# frozen_string_literal: true

require 'base64'
require 'digest'
require_relative '../model_spec_helper'
require_relative '../../lib/oauth_tokens'
require_relative '../../lib/sign_in_grant'

describe OauthTokens do
  cover 'OauthTokens*'

  before do
    @now = Time.now
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    team = Team.create(name: 'Payments')
    TeamMembership.create(team_id: team.id, person_id: @alice.id, working: true)
    @request = OauthRequest::Request.new(
      client_id: 'https://claude.ai/oauth/claude-code-client-metadata', redirect_uri: 'http://localhost:4000/callback',
      state: 'abc', challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      resource: "#{ENV.fetch('BASE_URL')}/mcp",
      name: 'Claude Code', recognised: true
    )
    @code = SignInGrant.call(person: @alice, request: @request, team_ids: [team.id], now: @now).code
    @other_code = SignInGrant.call(person: @alice, request: @request, team_ids: [team.id], now: @now).code
  end

  def verifier
    'mainline-test-verifier-0123456789-abcdefghijklmnop'
  end

  def exchange(now: @now, **changes)
    params = { 'grant_type' => 'authorization_code', 'code' => @code, 'code_verifier' => verifier,
               'client_id' => @request.client_id, 'redirect_uri' => @request.redirect_uri, 'resource' => @request.resource }
    OauthTokens.call(params.merge(changes.transform_keys(&:to_s)).compact, now: now)
  end

  def refresh(token, now: @now, client_id: @request.client_id)
    OauthTokens.call({ 'grant_type' => 'refresh_token', 'refresh_token' => token, 'client_id' => client_id }.compact, now: now)
  end

  def grant(code = @code)
    OauthGrant[DB[:oauth_codes].first(code_hash: Digest::SHA256.hexdigest(code))[:grant_id]]
  end

  def kept(table, token)
    DB[table].first(token_hash: Digest::SHA256.hexdigest(token))
  end

  describe 'exchanging a code' do
    it 'gives a bearer access token for an hour and a refresh token, kept only as digests, for the grant' do
      tokens = exchange.tokens

      assert_equal ['Bearer', 3600, 'mainline:read'], tokens.values_at(:token_type, :expires_in, :scope)
      assert_equal [grant.id, grant.id], [kept(:oauth_access_tokens, tokens[:access_token])[:grant_id],
                                          kept(:oauth_refresh_tokens, tokens[:refresh_token])[:grant_id]]
      assert_in_delta (@now + 3600).to_f, kept(:oauth_access_tokens, tokens[:access_token])[:expires_at].to_f, 1
      assert_in_delta (@now + (60 * 86_400)).to_f, kept(:oauth_refresh_tokens, tokens[:refresh_token])[:expires_at].to_f, 1
      assert_equal [43, 43], [tokens[:access_token].length, tokens[:refresh_token].length]
    end

    it 'takes a code once, and revokes its sign-in, and only that one, when it comes again' do
      tokens = exchange.tokens

      assert_equal 'invalid_grant', exchange.error
      refute_nil grant.revoked_at
      assert_equal 'invalid_grant', refresh(tokens[:refresh_token]).error
      assert_nil grant(@other_code).revoked_at
      assert_nil exchange(code: @other_code).error
    end

    it 'takes a code until its minute is up' do
      assert_nil exchange(now: @now + 59).error
    end

    it 'takes no code after its minute' do
      assert_equal 'invalid_grant', exchange(now: @now + 61).error
    end

    it 'refuses the wrong verifier, app, address or resource, and keeps the code for the right ones' do
      [{ code_verifier: "#{verifier}x" }, { client_id: 'https://chatgpt.com/oauth/client.json' },
       { redirect_uri: 'http://localhost:4000/other' }, { resource: 'https://elsewhere.example/mcp' },
       { code: 'not-a-code' }].each do |change|
        assert_equal 'invalid_grant', exchange(**change).error, change.inspect
      end

      assert_nil exchange.error
    end

    it 'refuses a code whose sign-in was revoked, while another sign-in is not' do
      grant.update(revoked_at: @now)

      assert_equal 'invalid_grant', exchange.error
      assert_nil exchange(code: @other_code).error
    end

    it 'needs every part of the exchange' do
      %w[code code_verifier client_id redirect_uri resource].each do |part|
        assert_equal 'invalid_request', exchange(part => '').error, part
        assert_equal 'invalid_request', exchange(part => nil).error, part
      end
    end
  end

  describe 'refreshing' do
    before { @tokens = exchange.tokens }

    it 'gives new tokens, and spends the old refresh token' do
      fresh = refresh(@tokens[:refresh_token]).tokens

      refute_equal @tokens[:access_token], fresh[:access_token]
      refute_equal @tokens[:refresh_token], fresh[:refresh_token]
      refute_nil kept(:oauth_refresh_tokens, @tokens[:refresh_token])[:used_at]
    end

    it 'spends only the refresh token used' do
      other = exchange(code: @other_code).tokens

      refresh(@tokens[:refresh_token])

      assert_nil refresh(other[:refresh_token]).error
    end

    it 'revokes the sign-in, and only that one, when a spent refresh token comes again' do
      fresh = refresh(@tokens[:refresh_token]).tokens

      assert_equal 'invalid_grant', refresh(@tokens[:refresh_token]).error
      refute_nil grant.revoked_at
      assert_equal 'invalid_grant', refresh(fresh[:refresh_token]).error
      assert_nil grant(@other_code).revoked_at
    end

    it 'refuses a refresh token after 60 days, an unknown one, or one for another app' do
      assert_equal 'invalid_grant', refresh(@tokens[:refresh_token], now: @now + (60 * 86_400) + 1).error
      assert_equal 'invalid_grant', refresh('not-a-token').error
      assert_equal 'invalid_grant', refresh(@tokens[:refresh_token], client_id: 'https://chatgpt.com/oauth/client.json').error
      assert_nil grant.revoked_at
      assert_nil refresh(@tokens[:refresh_token]).error
    end

    it 'refuses a refresh token once its sign-in is revoked, while another sign-in is not' do
      other = exchange(code: @other_code).tokens
      grant.update(revoked_at: @now)

      assert_equal 'invalid_grant', refresh(@tokens[:refresh_token]).error
      assert_nil refresh(other[:refresh_token]).error
    end

    it 'needs the refresh token and the app' do
      assert_equal 'invalid_request', refresh('').error
      assert_equal 'invalid_request', refresh(nil).error
      assert_equal 'invalid_request', refresh(@tokens[:refresh_token], client_id: nil).error
      assert_equal 'invalid_request', refresh(@tokens[:refresh_token], client_id: '').error
    end
  end

  it 'offers only codes and refresh tokens, and needs to be told which' do
    assert_equal 'unsupported_grant_type', OauthTokens.call({ 'grant_type' => 'client_credentials' }, now: @now).error
    assert_equal 'invalid_request', OauthTokens.call({}, now: @now).error
  end
end
