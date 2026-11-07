# frozen_string_literal: true

module RevokeOauthToken
  def self.call(provider, token)
    return unless token

    case provider
    when 'google_oauth2'
      Net::HTTP.post_form(
        URI('https://oauth2.googleapis.com/revoke'),
        'token' => token
      )
    when 'github'
      uri = URI("https://api.github.com/applications/#{ENV.fetch('GH_OAUTH_CLIENT_ID')}/token")
      req = Net::HTTP::Delete.new(uri)
      req.basic_auth(ENV.fetch('GH_OAUTH_CLIENT_ID'), ENV.fetch('GH_OAUTH_CLIENT_SECRET'))
      req.content_type = 'application/json'
      req.body = { access_token: token }.to_json
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    end
  rescue StandardError => e
    Sentry.capture_exception(e) if Sentry.initialized?
    nil
  end
end
