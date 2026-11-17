# frozen_string_literal: true

require 'base64'
require 'digest'
require 'rack/utils'
require 'securerandom'
require_relative 'oauth_metadata'

# What /oauth/token gives a coding agent's app. A code from an approved
# sign-in, with the PKCE verifier only the app knows, for the same app,
# address and resource it was given for, buys an access token for an hour and
# a refresh token for 60 days. A code works once, within its minute; a refresh
# token works once and comes back new. A spent code or refresh token used
# again revokes the sign-in, since only someone who stole it would use it
# twice. Tokens are kept only as digests.
module OauthTokens
  ACCESS_LIFETIME = 3600
  REFRESH_LIFETIME = 60 * 86_400
  EXCHANGE = %w[code code_verifier client_id redirect_uri resource].freeze

  Answer = Struct.new(:tokens, :error)

  def self.call(params, now: Time.now)
    case params['grant_type']
    when 'authorization_code' then exchange(params, now)
    when 'refresh_token' then refresh(params, now)
    when nil then Answer.new(nil, 'invalid_request')
    else Answer.new(nil, 'unsupported_grant_type')
    end
  end

  def self.exchange(params, now)
    return Answer.new(nil, 'invalid_request') unless EXCHANGE.all? { |part| given?(params[part]) }

    code = find_code(digest(params.fetch('code')))
    return Answer.new(nil, 'invalid_grant') unless code && live?(code.fetch(:grant_id))
    return Answer.new(nil, 'invalid_grant') unless code.fetch(:expires_at) > now && bound?(code, params)
    return spent(code.fetch(:grant_id), now) unless claimed?(DB[:oauth_codes], code.fetch(:id), now)

    issue(code.fetch(:grant_id), now)
  end

  def self.refresh(params, now)
    return Answer.new(nil, 'invalid_request') unless given?(params['refresh_token']) && given?(params['client_id'])

    token = find_refresh(digest(params.fetch('refresh_token')))
    grant = token && DB[:oauth_grants].first(id: token.fetch(:grant_id), revoked_at: nil)
    return Answer.new(nil, 'invalid_grant') unless grant && grant.fetch(:client_id) == params.fetch('client_id')
    return Answer.new(nil, 'invalid_grant') unless token.fetch(:expires_at) > now
    return spent(grant.fetch(:id), now) unless claimed?(DB[:oauth_refresh_tokens], token.fetch(:id), now)

    issue(grant.fetch(:id), now)
  end

  def self.find_code(digest)
    DB[:oauth_codes].first(code_hash: digest)
  end

  def self.find_refresh(digest)
    DB[:oauth_refresh_tokens].first(token_hash: digest)
  end

  # Marks a code or refresh token used, in one update that only an unused one
  # passes. Of two requests that looked it up at the same moment, only one
  # changes the row; the other is refused as a second use.
  def self.claimed?(table, id, now)
    table.where(id: id, used_at: nil).update(used_at: now) == 1
  end

  # One value, and not an empty one: a field sent twice arrives as a list.
  def self.given?(value)
    value.is_a?(String) && !value.empty?
  end

  def self.live?(grant_id)
    DB[:oauth_grants].where(id: grant_id, revoked_at: nil).any?
  end

  # The code was given for this app, address and resource, and the verifier
  # is the one its challenge was made from.
  def self.bound?(code, params)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(params.fetch('code_verifier')), padding: false)
    code.fetch_values(:client_id, :redirect_uri, :resource) == params.fetch_values('client_id', 'redirect_uri', 'resource') &&
      Rack::Utils.secure_compare(challenge, code.fetch(:code_challenge))
  end

  def self.spent(grant_id, now)
    DB[:oauth_grants].where(id: grant_id).update(revoked_at: now)
    Answer.new(nil, 'invalid_grant')
  end

  def self.issue(grant_id, now)
    access = SecureRandom.urlsafe_base64(32)
    refresh = SecureRandom.urlsafe_base64(32)
    DB[:oauth_access_tokens].insert(grant_id: grant_id, token_hash: digest(access), expires_at: now + ACCESS_LIFETIME)
    DB[:oauth_refresh_tokens].insert(grant_id: grant_id, token_hash: digest(refresh), expires_at: now + REFRESH_LIFETIME)
    Answer.new({ access_token: access, token_type: 'Bearer', expires_in: ACCESS_LIFETIME, refresh_token: refresh,
                 scope: OAuthMetadata::SCOPE })
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  private_class_method :exchange, :refresh, :find_code, :find_refresh, :claimed?, :given?, :live?, :bound?, :spent, :issue, :digest
end
