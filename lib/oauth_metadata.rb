# frozen_string_literal: true

# What a coding agent's client reads before it signs in: the MCP server as a
# protected resource (RFC 9728), signed in to by this same install. The
# document is fixed, built from the install's address, so serving it reads
# nothing.
module OAuthMetadata
  SCOPE = 'mainline:read'

  def self.protected_resource(base_url = ENV.fetch('BASE_URL'))
    { resource: "#{base_url}/mcp", authorization_servers: [base_url], scopes_supported: [SCOPE],
      bearer_methods_supported: ['header'] }
  end
end
