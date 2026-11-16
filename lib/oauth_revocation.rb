# frozen_string_literal: true

require 'digest'

# A coding agent's app signing itself out at /oauth/revoke (RFC 7009). Either
# of its tokens ends the whole sign-in, so neither works again. A token
# Mainline does not know gets the same answer as one it revoked, so the
# answer says nothing about which tokens exist. Only the app a token was
# given to may revoke it; personal tokens are revoked on the Coding agents
# page.
module OauthRevocation
  Answer = Struct.new(:error)

  def self.call(params, now: Time.now)
    token, client_id = params.values_at('token', 'client_id')
    return Answer.new('invalid_request') if token.to_s.empty? || client_id.to_s.empty?

    grant = grant_of(Digest::SHA256.hexdigest(token))
    return Answer.new unless grant
    return Answer.new('unauthorized_client') unless grant.fetch(:client_id) == client_id

    DB[:oauth_grants].where(id: grant.fetch(:id), revoked_at: nil).update(revoked_at: now)
    Answer.new
  end

  def self.grant_of(digest)
    grant_id = DB[:oauth_refresh_tokens].where(token_hash: digest).get(:grant_id) ||
               DB[:oauth_access_tokens].where(token_hash: digest).get(:grant_id)
    DB[:oauth_grants].first(id: grant_id)
  end

  private_class_method :grant_of
end
