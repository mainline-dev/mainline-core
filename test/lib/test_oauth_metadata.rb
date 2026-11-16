# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/oauth_metadata'

describe OAuthMetadata do
  cover 'OAuthMetadata*'

  it 'describes the MCP server at an install as signed in to by the install itself' do
    expected = { resource: 'https://example.test/mcp', authorization_servers: ['https://example.test'],
                 scopes_supported: ['mainline:read'], bearer_methods_supported: ['header'] }

    assert_equal expected, OAuthMetadata.protected_resource('https://example.test')
  end

  it 'uses the address the app runs at by default' do
    assert_equal "#{ENV.fetch('BASE_URL')}/mcp", OAuthMetadata.protected_resource[:resource]
  end
end
