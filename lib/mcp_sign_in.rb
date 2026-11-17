# frozen_string_literal: true

require_relative 'oauth_setting'

# What /mcp answers a request with no token, or one that is not a live one:
# sign in, as the metadata at the link describes. With OAuth off there is no
# sign-in to point at, so the answer asks for a token and nothing more. The
# answer reads nothing, and the one to a request with no token is never rate
# limited, since every sign-in starts with it.
module McpSignIn
  RESOURCE_METADATA = "#{ENV.fetch('BASE_URL')}/.well-known/oauth-protected-resource/mcp".freeze
  BODY = "This is Mainline's MCP endpoint. Connect to it from a coding agent."
  INVALID_BODY = 'That token is not valid: it has expired, was revoked or was never made. ' \
                 'Sign in again, or make a new personal token on the Coding agents page.'

  def self.challenge
    OauthSetting.on? ? %(Bearer resource_metadata="#{RESOURCE_METADATA}", scope="mainline:read") : 'Bearer'
  end

  def self.invalid_token
    return 'Bearer error="invalid_token"' unless OauthSetting.on?

    %(Bearer error="invalid_token", resource_metadata="#{RESOURCE_METADATA}", scope="mainline:read")
  end

  # Whether the request brings a token, so it goes on to be checked.
  def self.token?(env)
    env['HTTP_AUTHORIZATION'].to_s.match?(/\ABearer\s+\S/i)
  end
end
