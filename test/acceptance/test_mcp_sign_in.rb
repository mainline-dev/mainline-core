# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

# /mcp is the one address coding agents connect to. A request with no token
# is asked to sign in, with a link to the metadata that says how. That answer
# is fixed: it reads nothing and is never rate limited, since every sign-in
# starts with it and many people share a client's address.
describe 'Signing in to the MCP server' do
  include MainlineDSL
  include McpDSL

  before do
    turn_oauth_on
  end

  def sign_in_challenge
    metadata = "#{ENV.fetch('BASE_URL')}/.well-known/oauth-protected-resource/mcp"
    %(Bearer resource_metadata="#{metadata}", scope="mainline:read")
  end

  it 'asks a coding agent with no token to sign in, pointing at the resource metadata' do
    response = ask_mcp(method: 'GET')

    assert_equal 401, response.status
    assert_equal sign_in_challenge, response.headers['WWW-Authenticate']
  end

  it 'asks a POST with no token the same way' do
    response = ask_mcp(method: 'POST')

    assert_equal [401, sign_in_challenge], [response.status, response.headers['WWW-Authenticate']]
  end

  it 'answers a browser it does not send to the page in plain text' do
    headers = {}
    # Hosted sends a browser to the page about the MCP server unless it carries
    # a token. A self-hosted install has no such page.
    response = browse('/mcp', headers: headers)

    assert_equal 401, response.status
    assert_equal 'text/plain', response.media_type
    refute_empty response.body
  end

  it 'never limits how often a coding agent is asked to sign in' do
    assert_equal [401], Array.new(30) { ask_mcp.status }.uniq
  end

  it 'asks without reading the database, where a form a person posts does' do
    assert_equal(0, database_queries_during { ask_mcp })
    refute_equal(0, database_queries_during { request_login_link('nobody@example.test') })
  end

  it 'is not refused by the check on forms' do
    assert_equal 401, with_csrf_checked { ask_mcp }.status
  end
end
