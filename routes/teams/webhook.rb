# frozen_string_literal: true

require 'bcrypt'

class Mainline
  hash_branch('teams', 'webhook') do |r|
    r.is do
      r.get do
        view 'teams/webhook'
      end

      r.post do
        unless @is_creator
          flash['error'] = 'Only the account holder can rotate the deploy webhook token'
          next r.redirect("/teams/#{@team.id}/webhook")
        end

        @generated_token = SecureRandom.hex(32)

        DB.transaction do
          unless @team.webhook_actor_id
            actor = Actor.create(kind: 'system', name: "#{@team.name} Webhook")
            @team.update(webhook_actor_id: actor.id)
          end

          @team.update(webhook_token: BCrypt::Password.create(@generated_token))
          RecordEvent.call(
            actor_id: @current_actor.id,
            entity:   @team,
            action:   'webhook_token_rotated',
            team_id:  @team.id
          )
        end

        @team.refresh
        view 'teams/webhook'
      end
    end
  end
end
