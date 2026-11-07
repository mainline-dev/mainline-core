# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe '.well-known/mcp.json' do
  include MainlineDSL

  it 'returns MCP server discovery JSON' do
    anon = HttpDriver.new
    resp = anon.get '/.well-known/mcp.json'

    assert_equal 200, resp.status
    assert_equal 'application/json', resp.content_type

    body = JSON.parse(resp.body)
    server = body.dig('mcpServers', 'mainline')

    assert_equal 'https://mainline.dev/mcp/{team_id}', server['url']
    assert_equal 'bearer', server.dig('authentication', 'type')
  end
end
