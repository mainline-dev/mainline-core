# frozen_string_literal: true

require_relative '../lib/mcp_auth'
require_relative '../lib/mcp_server'

MCP_TRANSPORT = MCP::Server::Transports::StreamableHTTPTransport.new(
  MainlineMCP.build_server, stateless: true, enable_json_response: true,
  allowed_hosts: [ENV.fetch('MAINLINE_HOST')]
)

class Mainline
  hash_branch('mcp') do |r|
    r.on String do |team_id|
      unless team_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
        response.status = 400
        response['Content-Type'] = 'application/json'
        next '{"error":"Replace YOUR_TEAM_ID with your actual team ID (a UUID from team settings)"}'
      end

      team = Team[team_id]
      unless team
        response.status = 404
        response['Content-Type'] = 'application/json'
        next %({"error":"Team not found. Check the ID in your team settings, or sign up at #{ENV.fetch('BASE_URL')}/signup"})
      end

      token = r.env['HTTP_AUTHORIZATION']&.delete_prefix('Bearer ')
      unless McpAuth.valid?(team, token)
        unless MCP_RATE_LIMITER.allow?(request.ip)
          response.status = 429
          response['Content-Type'] = 'application/json'
          next '{"error":"too many requests"}'
        end
        response.status = 401
        response['Content-Type'] = 'application/json'
        next '{"error":"unauthorized"}'
      end

      if team.suspended?
        response.status = 403
        response['Content-Type'] = 'application/json'
        next '{"error":"team inactive"}'
      end

      SetTeamContext.call(team.id)
      Thread.current[:mcp_team_id] = team.id
      Thread.current[:mcp_user_agent] = r.env['HTTP_USER_AGENT']
      begin
        status, headers, body = MCP_TRANSPORT.call(r.env)
        response.status = status
        headers.each { |k, v| response[k] = v }
        chunks = []
        body.each { |chunk| chunks << chunk } if body.respond_to?(:each)
        r.halt [status, headers, chunks]
      ensure
        Thread.current[:mcp_team_id] = nil
        Thread.current[:mcp_user_agent] = nil
      end
    end
  end
end
