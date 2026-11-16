# frozen_string_literal: true

# What a coding agent's client reads before it signs in: the MCP server as a
# protected resource (RFC 9728), and this same install as the server that
# signs people in for it (RFC 8414). Both are fixed, built from the install's
# address, so serving them reads nothing.
module OAuthMetadata
  SCOPE = 'mainline:read'

  def self.protected_resource(base_url = ENV.fetch('BASE_URL'))
    { resource: "#{base_url}/mcp", authorization_servers: [base_url], scopes_supported: [SCOPE],
      bearer_methods_supported: ['header'] }
  end

  # Clients identify themselves by a Client ID Metadata Document and sign in as
  # public clients with PKCE, so there is no registration endpoint and no
  # client secret. Every redirect back to a client carries an iss equal to the
  # issuer, which lets ChatGPT and Codex keep one stable redirect address.
  def self.authorization_server(base_url = ENV.fetch('BASE_URL'))
    {
      issuer:                                         base_url,
      authorization_endpoint:                         "#{base_url}/oauth/authorize",
      token_endpoint:                                 "#{base_url}/oauth/token",
      revocation_endpoint:                            "#{base_url}/oauth/revoke",
      scopes_supported:                               [SCOPE],
      response_types_supported:                       ['code'],
      grant_types_supported:                          %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported:          ['none'],
      code_challenge_methods_supported:               ['S256'],
      client_id_metadata_document_supported:          true,
      authorization_response_iss_parameter_supported: true
    }
  end
end
