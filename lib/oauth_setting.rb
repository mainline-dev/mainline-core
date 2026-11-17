# frozen_string_literal: true

# Whether coding agents can sign in with OAuth on this install. It is the
# setting OAUTH_ENABLED, on only when it says true: unset, as it is until an
# install chooses to offer sign-in, every OAuth address and both metadata
# documents are not there, and only personal tokens work at /mcp.
module OauthSetting
  NAME = 'OAUTH_ENABLED'

  def self.on?(env = ENV)
    env[NAME] == 'true'
  end
end
