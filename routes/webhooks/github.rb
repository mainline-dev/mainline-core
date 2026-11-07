# frozen_string_literal: true

require 'openssl'

class Mainline
  hash_branch('webhooks', 'github') do |r|
    r.hash_branches('webhooks/github')

    r.post do
      body = r.body.read
      signature = r.env['HTTP_X_HUB_SIGNATURE_256']

      unless verify_github_signature(body, signature)
        response.status = 401
        next '{}'
      end

      event = r.env['HTTP_X_GITHUB_EVENT']
      payload = JSON.parse(body, symbolize_names: true)
      BypassRLS.call { CIMonitor::GithubWebhookHandler.new(event, payload).call }
      '{}'
    end
  end

  def verify_github_signature(body, signature)
    secret = ENV.fetch('CI_MONITOR_GITHUB_WEBHOOK_SECRET')
    return false unless signature

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    Rack::Utils.secure_compare(expected, signature)
  end
end
