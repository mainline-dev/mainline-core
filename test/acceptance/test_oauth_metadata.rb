# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

# Before it signs in, a coding agent's client reads two documents: the MCP
# server described as a protected resource, and this app described as the
# server that signs people in for it. Both are fixed, built from the install's
# address, and must match each other exactly.
describe 'How a coding agent finds out how to sign in' do
  include MainlineDSL
  include McpDSL

  before { turn_oauth_on }

  def base_url
    ENV.fetch('BASE_URL')
  end

  %w[/.well-known/oauth-protected-resource/mcp /.well-known/oauth-protected-resource].each do |path|
    it "describes the MCP server as a protected resource at #{path}" do
      response = fetch_metadata(path)

      assert_equal [200, 'application/json'], [response.status, response.media_type]
      expected = { 'resource' => "#{base_url}/mcp", 'authorization_servers' => [base_url],
                   'scopes_supported' => ['mainline:read'], 'bearer_methods_supported' => ['header'] }

      assert_equal expected, JSON.parse(response.body)
    end
  end

  it 'answers at the address the request to sign in links to' do
    link = ask_mcp.headers['WWW-Authenticate'][/resource_metadata="([^"]+)"/, 1]

    assert_equal 200, fetch_metadata(URI(link).path).status
  end

  it 'describes this install as the server that signs people in, by Client ID Metadata Document only' do
    response = fetch_metadata('/.well-known/oauth-authorization-server')
    expected = {
      'issuer'                                         => base_url,
      'authorization_endpoint'                         => "#{base_url}/oauth/authorize",
      'token_endpoint'                                 => "#{base_url}/oauth/token",
      'revocation_endpoint'                            => "#{base_url}/oauth/revoke",
      'scopes_supported'                               => ['mainline:read'],
      'response_types_supported'                       => ['code'],
      'grant_types_supported'                          => %w[authorization_code refresh_token],
      'token_endpoint_auth_methods_supported'          => ['none'],
      'code_challenge_methods_supported'               => ['S256'],
      'client_id_metadata_document_supported'          => true,
      'authorization_response_iss_parameter_supported' => true
    }

    assert_equal [200, 'application/json'], [response.status, response.media_type]
    assert_equal expected, JSON.parse(response.body)
  end

  it 'names itself exactly as the protected resource names it' do
    issuer = JSON.parse(fetch_metadata('/.well-known/oauth-authorization-server').body)['issuer']
    servers = JSON.parse(fetch_metadata('/.well-known/oauth-protected-resource/mcp').body)['authorization_servers']

    assert_equal [issuer], servers
  end

  it 'describes both without reading the database' do
    queries = database_queries_during {
      fetch_metadata('/.well-known/oauth-protected-resource/mcp')
      fetch_metadata('/.well-known/oauth-authorization-server')
    }

    assert_equal 0, queries
  end
end
