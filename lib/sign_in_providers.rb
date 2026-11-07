# frozen_string_literal: true

# The sign-in providers this install offers. Each needs an OAuth app
# registered with the provider and its client id and secret set; a client id
# of "disabled" leaves that provider out, with no button and no route, so an
# install can run on email accounts alone.
module SignInProviders
  CLIENT_IDS = {
    'google_oauth2' => 'GOOGLE_CLIENT_ID',
    'github'        => 'GH_OAUTH_CLIENT_ID',
    'gitlab'        => 'GITLAB_CLIENT_ID'
  }.freeze
  OFF = 'disabled'

  def self.enabled?(provider)
    CLIENT_IDS.key?(provider) && ENV.fetch(CLIENT_IDS.fetch(provider)) != OFF
  end

  def self.any?
    CLIENT_IDS.keys.any? { |provider| enabled?(provider) }
  end
end
