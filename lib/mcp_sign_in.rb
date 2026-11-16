# frozen_string_literal: true

# What /mcp answers a request with no token: sign in, as the metadata at the
# link describes. The answer is fixed, so giving it reads nothing, and it is
# never rate limited, since every sign-in starts with it.
module McpSignIn
  RESOURCE_METADATA = "#{ENV.fetch('BASE_URL')}/.well-known/oauth-protected-resource/mcp".freeze
  CHALLENGE = %(Bearer resource_metadata="#{RESOURCE_METADATA}", scope="mainline:read").freeze
  BODY = "This is Mainline's MCP endpoint. Connect to it from a coding agent."
end
