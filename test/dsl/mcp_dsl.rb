# frozen_string_literal: true

# MCP client steps over HTTP. Needs a spec that includes Rack::Test (the web
# spec helper) and a @team.
module McpDSL
  def generate_mcp_token
    driver.submit_generate_mcp_token(@team)
    @team.refresh
    @mcp_token = driver.last_mcp_token
  end

  # What a browser's address bar asks for.
  BROWSER_ACCEPT = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

  # A page, as a browser asks for it, with any extra headers it sends.
  def browse(path, headers: {})
    get(path, {}, { 'HTTP_ACCEPT' => BROWSER_ACCEPT, 'HTTP_HOST' => ENV.fetch('MAINLINE_HOST') }.merge(headers))
    last_response
  end

  # A request to /mcp from a coding agent that has not signed in.
  def ask_mcp(method: 'POST')
    headers = { 'HTTP_ACCEPT' => 'application/json, text/event-stream', 'HTTP_HOST' => ENV.fetch('MAINLINE_HOST') }
    if method == 'GET'
      get('/mcp', {}, headers)
    else
      body = { jsonrpc: '2.0', id: 1, method: 'initialize',
               params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } } }
      post('/mcp', JSON.generate(body), headers.merge('CONTENT_TYPE' => 'application/json'))
    end
    last_response
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

  # The text a tool call returned, and whether it was an error.
  def mcp_tool_text(response)
    result = JSON.parse(response.body)['result']
    [result['content'].find { |c| c['type'] == 'text' }['text'], result['isError']]
  end

  # The tools the server offers, as a client lists them.
  def mcp_list_tools(team_id: @team.id, token: nil)
    token ||= @mcp_token
    post(
      "/mcp/#{team_id}",
      JSON.generate({ jsonrpc: '2.0', id: 3, method: 'tools/list' }),
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'HTTP_HOST'          => ENV.fetch('MAINLINE_HOST')
    )
    JSON.parse(last_response.body).dig('result', 'tools')
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
