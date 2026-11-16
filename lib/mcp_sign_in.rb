# frozen_string_literal: true

# What /mcp answers a request with no token: sign in, as the metadata at the
# link describes. The answer is fixed, so giving it reads nothing, and it is
# never rate limited, since every sign-in starts with it.
module McpSignIn
  RESOURCE_METADATA = "#{ENV.fetch('BASE_URL')}/.well-known/oauth-protected-resource/mcp".freeze
  CHALLENGE = %(Bearer resource_metadata="#{RESOURCE_METADATA}", scope="mainline:read").freeze
  BODY = "This is Mainline's MCP endpoint. Connect to it from a coding agent."
  # A token that is not a live one: sign in again, or make a new token.
  INVALID_TOKEN = %(Bearer error="invalid_token", resource_metadata="#{RESOURCE_METADATA}", scope="mainline:read").freeze
  INVALID_BODY = 'That token is not valid: it has expired, was revoked or was never made. ' \
                 'Sign in again, or make a new personal token on the Coding agents page.'

  # Whether the request brings a token, so it goes on to be checked.
  def self.token?(env)
    env['HTTP_AUTHORIZATION'].to_s.match?(/\ABearer\s+\S/i)
  end
end
