# frozen_string_literal: true

# MCP client steps over HTTP. Needs a spec that includes Rack::Test (the web
# spec helper) and a @team.
module McpDSL
  def generate_mcp_token
    driver.submit_generate_mcp_token(@team)
    @team.refresh
    @mcp_token = driver.last_mcp_token
  end

  def mcp_initialize(team_id: @team.id, token: nil)
    token ||= @mcp_token
    post(
      "/mcp/#{team_id}",
      JSON.generate({
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: '2025-03-26', capabilities: {},
                  clientInfo: { name: 'test', version: '1.0' } }
      }),
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'HTTP_HOST'          => ENV.fetch('MAINLINE_HOST')
    )
    last_response
  end

  def mcp_call_tool(name, arguments: {}, team_id: @team.id, token: nil, user_agent: nil)
    token ||= @mcp_token
    headers = {
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'HTTP_HOST'          => ENV.fetch('MAINLINE_HOST')
    }
    headers['HTTP_USER_AGENT'] = user_agent if user_agent
    post(
      "/mcp/#{team_id}",
      JSON.generate({
        jsonrpc: '2.0', id: 2, method: 'tools/call',
        params: { name: name, arguments: arguments }
      }),
      headers
    )
    last_response
  end
end
