# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/machine_paths'

describe MachinePaths do
  cover 'MachinePaths*'

  it 'includes the MCP endpoint, old and new' do
    assert MachinePaths.machine?('/mcp')
    assert MachinePaths.machine?('/mcp/00000000-0000-4000-8000-000000000000')
  end

  it 'includes the OAuth endpoints a client calls without a browser' do
    assert MachinePaths.machine?('/oauth/token')
    assert MachinePaths.machine?('/oauth/revoke')
  end

  it 'includes the metadata under /.well-known/, the API and webhooks' do
    assert MachinePaths.machine?('/.well-known/oauth-authorization-server')
    assert MachinePaths.machine?('/api/teams/x/deploys')
    assert MachinePaths.machine?('/webhooks/github')
  end

  it 'leaves out the pages people visit, even those whose address starts the same way' do
    %w[/mcp-server /mcpx /oauth/authorize /oauth/token/x /api /login /].each do |path|
      refute MachinePaths.machine?(path), path
    end
  end
end
