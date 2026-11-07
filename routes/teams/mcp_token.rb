# frozen_string_literal: true

require 'bcrypt'
require_relative '../../lib/mcp_auth'

class Mainline
  hash_branch('teams', 'mcp_token') do |r|
    r.is do
      r.get do
        view 'teams/mcp_token'
      end

      r.post do
        unless @is_creator
          flash['error'] = 'Only the account holder can rotate the MCP token'
          next r.redirect("/teams/#{@team.id}/mcp_token")
        end

        @generated_token = SecureRandom.hex(32)
        DB.transaction do
          @team.update(mcp_token: BCrypt::Password.create(@generated_token))
          RecordEvent.call(
            actor_id: @current_actor.id,
            entity:   @team,
            action:   'mcp_token_rotated',
            team_id:  @team.id
          )
        end
        McpAuth.clear_cache(@team.id)
        @team.refresh
        view 'teams/mcp_token'
      end
    end
  end
end
