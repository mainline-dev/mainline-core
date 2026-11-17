# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'
require_relative '../dsl/oauth_dsl'

# Signing coding agents in with OAuth is behind a setting, OAUTH_ENABLED, off
# unless it is set to true. Off, every OAuth address and both metadata
# documents are not there, and /mcp asks for a token without pointing a
# client at a sign-in it cannot do. Personal tokens work either way.
describe 'Signing coding agents in, as a setting' do
  include MainlineDSL
  include McpDSL
  include OauthDsl

  before do
    MCP_RATE_LIMITER.reset
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
  end

  after { forget_client_documents }

  def oauth_addresses
    [-> { start_sign_in }, -> { ask_for_token('grant_type' => 'authorization_code') }, -> { revoke_token('not-a-token') },
     -> { fetch_metadata('/.well-known/oauth-protected-resource/mcp') },
     -> { fetch_metadata('/.well-known/oauth-protected-resource') },
     -> { fetch_metadata('/.well-known/oauth-authorization-server') }]
  end

  def personal_token
    create_personal_token(name: 'build runner', teams: [@team], expires_on: Date.today + 30)
  end

  describe 'off, as it is unless set' do
    it 'has no OAuth addresses and no metadata documents' do
      assert(oauth_addresses.all? { |ask| not_there?(&ask) })
    end

    it 'asks for a token at /mcp without pointing at a sign-in' do
      asked = ask_mcp
      refused = connect_mcp(token: 'not-a-token')

      assert_equal [401, 401], [asked.status, refused.status]
      refute_includes asked.headers['WWW-Authenticate'], 'resource_metadata'
      refute_includes refused.headers['WWW-Authenticate'], 'resource_metadata'
      assert_includes refused.headers['WWW-Authenticate'], 'error="invalid_token"'
    end

    it 'takes a personal token at /mcp' do
      assert_equal 200, connect_mcp(token: personal_token).status
    end

    it "takes no app's token at /mcp, even one given while it was on" do
      turn_oauth_on
      client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback'])
      start_sign_in
      approve_sign_in
      tokens = exchange_code(sent_back['code'])

      turn_oauth_off

      assert_equal 401, connect_mcp(token: tokens['access_token']).status
    end
  end

  describe 'on' do
    before { turn_oauth_on }

    it 'has its metadata documents, and its sign-in page' do
      client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://localhost/callback'])

      refute(oauth_addresses.any? { |ask| not_there?(&ask) })
    end

    it 'asks for a token at /mcp, pointing at how to sign in' do
      assert_includes ask_mcp.headers['WWW-Authenticate'], 'resource_metadata'
    end

    it 'takes a personal token at /mcp' do
      assert_equal 200, connect_mcp(token: personal_token).status
    end
  end
end
