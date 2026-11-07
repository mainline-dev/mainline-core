# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/mcp_server'

# Core announces its MCP server as it builds it, so code in its own files can
# add tools.
describe 'MCP server announcement' do
  it 'announces the server it builds' do
    heard = nil
    sub = CoreEvents.subscribe(:mcp_server_built) { |event| heard = event[:server] }

    server = MainlineMCP.build_server

    assert_same server, heard
  ensure
    CoreEvents.unsubscribe(sub)
  end
end
