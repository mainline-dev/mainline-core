# frozen_string_literal: true

require_relative '../client_documents'

# What a driver sets up and looks up for coding agents signing in: the
# documents apps publish, and what a sign-in or a personal token was given.
module OauthRecords
  def publish_client_document(client_id, name:, redirect_uris:)
    @client_documents ||= ClientDocuments.new
    ClientMetadata.network = @client_documents
    @client_documents.publish(client_id, JSON.generate(client_id: client_id, client_name: name, redirect_uris: redirect_uris))
  end

  def forget_client_documents
    ClientMetadata.network = HttpsFetch
    ClientMetadata.forget
    ClientMetadata::LIMITER.reset
  end

  def teams_given_by_last_sign_in
    grant = OauthGrant.exclude(client_id: nil).order(:created_at).last
    return unless grant

    BypassRLS.call { Team.where(id: DB[:oauth_grant_teams].where(grant_id: grant.id).select(:team_id)).order(:name).select_map(:name) }
  end

  def revoke_last_sign_in
    OauthGrant.exclude(client_id: nil).order(:created_at).last.update(revoked_at: Time.now)
  end

  def personal_token_nobody_made
    PersonalToken.generate
  end
end
