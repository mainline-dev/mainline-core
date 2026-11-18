# frozen_string_literal: true

# MCP client steps over HTTP. Needs a spec that includes Rack::Test (the web
# spec helper) and a @team.
module McpDSL
  # A coding agent set up as a person sets one up: a personal token for the
  # team, made by whoever is signed in.
  def connect_coding_agent
    @mcp_token = create_personal_token(name: 'coding agent', teams: [@team], expires_on: Date.today + 30)
  end

  # What an agent set up for the old address of one team alone,
  # /mcp/<team id>, is answered now.
  def ask_the_old_team_address
    body = { jsonrpc: '2.0', id: 1, method: 'initialize',
             params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } } }
    post("/mcp/#{@team.id}", JSON.generate(body), signed_in_headers(@mcp_token))
    last_response
  end

  # Where a team's token page was, at /teams/<team id>/mcp_token.
  def visit_the_old_team_token_page
    driver.visit_old_team_token_page(@team)
  end

  # What a browser's address bar asks for.
  BROWSER_ACCEPT = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

  # A page, as a browser asks for it, with any extra headers it sends.
  def browse(path, headers: {})
    get(path, {}, { 'HTTP_ACCEPT' => BROWSER_ACCEPT, 'HTTP_HOST' => ENV.fetch('MAINLINE_HOST') }.merge(headers))
    last_response
  end

  # A metadata document, as a coding agent's client fetches it.
  def fetch_metadata(path)
    get(path, {}, { 'HTTP_ACCEPT' => 'application/json', 'HTTP_HOST' => ENV.fetch('MAINLINE_HOST') })
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

  # How /mcp answers a coding agent that connects with this token: a personal
  # token, or an OAuth access token.
  def connect_mcp(token:, from: nil)
    body = { jsonrpc: '2.0', id: 1, method: 'initialize',
             params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } } }
    headers = signed_in_headers(token)
    headers['REMOTE_ADDR'] = from if from
    post('/mcp', JSON.generate(body), headers)
    last_response
  end

  # A header of the last answer /mcp gave.
  def last_answer_header(name)
    last_response.headers[name]
  end

  # A tool call to /mcp with this token.
  # Each read of the story a coding agent made, oldest first: the app it came
  # through and the tool that made it.
  def agent_reads_of(story)
    driver.events_of(story, action: 'agent_read').map { |event| event.after_state.values_at('client', 'tool') }
  end

  def call_mcp(name, token:, arguments: {})
    body = { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: name, arguments: arguments } }
    post('/mcp', JSON.generate(body), signed_in_headers(token))
    last_response
  end

  # A tool call's answer read as JSON, for the tools that answer in JSON.
  def mcp_json(response)
    JSON.parse(mcp_tool_text(response).first)
  end

  def signed_in_headers(token)
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}", 'HTTP_HOST' => ENV.fetch('MAINLINE_HOST') }
  end

  def mcp_initialize(token: nil)
    token ||= @mcp_token
    post(
      '/mcp',
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
  def mcp_list_tools(token: nil)
    token ||= @mcp_token
    post(
      '/mcp',
      JSON.generate({ jsonrpc: '2.0', id: 3, method: 'tools/list' }),
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'HTTP_HOST'          => ENV.fetch('MAINLINE_HOST')
    )
    JSON.parse(last_response.body).dig('result', 'tools')
  end

  def mcp_call_tool(name, arguments: {}, token: nil, user_agent: nil)
    token ||= @mcp_token
    headers = {
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'HTTP_HOST'          => ENV.fetch('MAINLINE_HOST')
    }
    headers['HTTP_USER_AGENT'] = user_agent if user_agent
    post(
      '/mcp',
      JSON.generate({
        jsonrpc: '2.0', id: 2, method: 'tools/call',
        params: { name: name, arguments: arguments }
      }),
      headers
    )
    last_response
  end
end
