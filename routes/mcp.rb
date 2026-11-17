# frozen_string_literal: true

require_relative '../lib/mcp_access'
require_relative '../lib/mcp_auth'
require_relative '../lib/mcp_server'

MCP_TRANSPORT = MCP::Server::Transports::StreamableHTTPTransport.new(
  MainlineMCP.build_server, stateless: true, enable_json_response: true,
  allowed_hosts: [ENV.fetch('MAINLINE_HOST')]
)

class Mainline
  hash_branch('mcp') do |r|
    # A coding agent with a personal token, or an app's access token. One with
    # no token never gets here: app.rb asks it to sign in.
    r.is do
      now = Time.now
      token = mcp_token(r)
      access = McpAccess.for_token(token, now: now)
      next mcp_invalid_token(McpAccess.grant_of(token)) unless access
      next mcp_too_many(1) unless MCP_GRANT_LIMITER.allow?(access.grant_id)

      unless access.readable?
        next mcp_refusal(403, 'None of the teams this coding agent was given can be read now: ' \
                              'each is suspended, or you are no longer on it.')
      end

      access.used(now)
      serve_mcp(r, access)
    end

    r.on String do |team_id|
      unless team_id.match?(McpAccess::UUID)
        next mcp_refusal(400, 'Replace YOUR_TEAM_ID with your actual team ID (a UUID from team settings)')
      end

      team = Team[team_id]
      next mcp_refusal(404, "Team not found. Check the ID in your team settings, or sign up at #{ENV.fetch('BASE_URL')}/signup") unless team

      unless McpAuth.valid?(team, mcp_token(r))
        next mcp_refusal(429, 'too many requests') unless MCP_RATE_LIMITER.allow?(request.ip)

        next mcp_refusal(401, 'unauthorized')
      end

      next mcp_refusal(403, 'team inactive') if team.suspended?

      SetTeamContext.call(team.id)
      serve_mcp(r, McpAccess.for_team(team))
    end
  end

  def mcp_token(req)
    req.env['HTTP_AUTHORIZATION'].to_s[/\ABearer\s+(\S+)\z/i, 1]
  end

  # Too many: try again once the limit lets another call through.
  def mcp_too_many(seconds)
    response['Retry-After'] = seconds.to_s
    mcp_refusal(429, 'too many requests')
  end

  def mcp_refusal(status, message)
    response.status = status
    response['Content-Type'] = 'application/json'
    JSON.generate(error: message)
  end

  # A token that is not a live one, asked to sign in again. One Mainline
  # issued counts against its own grant, so the many people who reach Mainline
  # from one platform's addresses never use up each other's allowance; only a
  # token matching nothing counts against the address it came from.
  def mcp_invalid_token(grant_id)
    return mcp_too_many(1) if grant_id && !MCP_GRANT_LIMITER.allow?(grant_id)
    return mcp_too_many(6) if grant_id.nil? && !MCP_UNKNOWN_TOKEN_LIMITER.allow?(request.ip)

    response.status = 401
    response['WWW-Authenticate'] = McpSignIn.invalid_token
    response['Content-Type'] = 'text/plain'
    McpSignIn::INVALID_BODY
  end

  # Hands the request to the MCP server, which reads with the access given.
  def serve_mcp(req, access)
    Thread.current[:mcp_access] = access
    Thread.current[:mcp_user_agent] = req.env['HTTP_USER_AGENT']
    status, headers, body = MCP_TRANSPORT.call(req.env)
    chunks = []
    body.each { |chunk| chunks << chunk } if body.respond_to?(:each)
    req.halt [status, headers, chunks]
  ensure
    Thread.current[:mcp_access] = nil
    Thread.current[:mcp_user_agent] = nil
  end
end
