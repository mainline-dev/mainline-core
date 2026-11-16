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
    assert_equal ENV.fetch('BASE_URL'), OAuthMetadata.authorization_server[:issuer]
  end

  it 'describes the install as the server that signs people in, for public clients with PKCE' do
    expected = {
      issuer:                                         'https://example.test',
      authorization_endpoint:                         'https://example.test/oauth/authorize',
      token_endpoint:                                 'https://example.test/oauth/token',
      revocation_endpoint:                            'https://example.test/oauth/revoke',
      scopes_supported:                               ['mainline:read'],
      response_types_supported:                       ['code'],
      grant_types_supported:                          %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported:          ['none'],
      code_challenge_methods_supported:               ['S256'],
      client_id_metadata_document_supported:          true,
      authorization_response_iss_parameter_supported: true
    }

    assert_equal expected, OAuthMetadata.authorization_server('https://example.test')
  end
end
