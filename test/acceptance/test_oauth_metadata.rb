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

  it 'describes the MCP server without reading the database' do
    assert_equal(0, database_queries_during { fetch_metadata('/.well-known/oauth-protected-resource/mcp') })
  end
end
