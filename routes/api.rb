# frozen_string_literal: true

require 'bcrypt'
require_relative '../lib/rate_limiter'

DEPLOY_RATE_LIMITER = SharedRateLimiter.new(name: 'deploy', capacity: 10, refill_rate: 0.2)

class Mainline
  hash_branch('api') do |r|
    response['Content-Type'] = 'application/json'

    r.on 'teams' do
      r.on String do |team_id|
        next unless team_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

        team = Team[team_id]
        unless team
          response.status = 404
          next '{}'
        end

        r.post 'deploys' do
          unless DEPLOY_AUTH_RATE_LIMITER.allow?(request.ip)
            response.status = 429
            response['Retry-After'] = '60'
            next '{"error":"too many requests"}'
          end

          SetTeamContext.call(team.id)
          token = r.env['HTTP_AUTHORIZATION']&.delete_prefix('Bearer ')

          unless team.webhook_token && BCrypt::Password.new(team.webhook_token) == token.to_s
            response.status = 401
            next '{"error":"unauthorized"}'
          end

          unless DEPLOY_RATE_LIMITER.allow?(team_id)
            response.status = 429
            response['Retry-After'] = '1'
            next '{"error":"rate limit exceeded"}'
          end

          if team.suspended?
            response.status = 403
            next '{"error":"team inactive"}'
          end

          begin
            body = JSON.parse(r.body.read)
          rescue JSON::ParserError
            response.status = 400
            next '{"error":"invalid JSON"}'
          end
          unless body.is_a?(Hash)
            response.status = 400
            next '{"error":"expected a JSON object"}'
          end

          deploy_actor = Actor[team.webhook_actor_id]
          unless deploy_actor
            response.status = 500
            next JSON.generate(error: 'Webhook actor not configured')
          end

          result = ReportDeploys.call(team: team, actor: deploy_actor, story_ids: Array(body['story_ids']), now: Time.now)
          unless result.success?
            response.status = 400
            next JSON.generate(error: result.error)
          end

          JSON.generate({ deployed: result.deployed })
        end
      end
    end

    response.status = 404
    '{}'
  end
end
