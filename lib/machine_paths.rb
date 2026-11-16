# frozen_string_literal: true

# The paths machines call without a browser session: coding agents and the
# OAuth clients behind them, deploy pipelines and webhooks. Each answers for
# itself, so only these skip the checks meant for people's browsers: the CSRF
# check and the hosted dev site's password. The same paths are the ones to
# exempt from Cloudflare's bot checks, which are set by hand.
module MachinePaths
  EXACT = %w[/mcp /oauth/token /oauth/revoke].freeze
  PREFIXES = %w[/mcp/ /.well-known/ /api/ /webhooks/].freeze

  def self.machine?(path)
    EXACT.include?(path) || path.start_with?(*PREFIXES)
  end
end
