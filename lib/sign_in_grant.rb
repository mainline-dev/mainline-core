# frozen_string_literal: true

require 'digest'
require 'securerandom'
require_relative 'bypass_rls'
require_relative 'map_access'
require_relative 'oauth_metadata'
require_relative 'oauth_request'

# What a person approves on the consent page: a grant to the app to read the
# teams they ticked, as them, and a code the app exchanges for its tokens.
# Only teams whose maps the person can open may be ticked, and at least one
# must be. The code works once, for a minute, and only for the app, address,
# PKCE challenge and resource it was given for; only its digest is kept.
module SignInGrant
  CODE_LIFETIME = 60

  Result = Struct.new(:code, :errors) do
    def success?
      errors.empty?
    end
  end

  def self.call(person:, request:, team_ids:, now: Time.now)
    team_ids = Array(team_ids).uniq
    errors = refusals(person, team_ids)
    return Result.new(nil, errors) unless errors.empty?

    # The request's own transaction holds the grant, its teams and its code
    # together.
    code = SecureRandom.urlsafe_base64(32)
    store(person, request, team_ids, code, now)
    Result.new(code, [])
  end

  def self.refusals(person, team_ids)
    [
      ('Tick at least one team.' if team_ids.empty?),
      ('Tick only teams whose maps you can open.' unless (team_ids - MapAccess.team_ids_for(person.id)).empty?)
    ].compact
  end

  def self.store(person, request, team_ids, code, now)
    # A recognised app keeps the name it gives itself; any other is known by
    # its site, as the consent page names it.
    grant = OauthGrant.create(person_id: person.id, client_id: request.client_id, scope: OAuthMetadata::SCOPE,
      resource: request.resource, name: (request.name if request.recognised))
    BypassRLS.call { team_ids.each { |team_id| DB[:oauth_grant_teams].insert(grant_id: grant.id, team_id: team_id) } }
    DB[:oauth_codes].insert(grant_id: grant.id, code_hash: Digest::SHA256.hexdigest(code), client_id: request.client_id,
      redirect_uri: request.redirect_uri, code_challenge: request.challenge, resource: request.resource,
      expires_at: now + CODE_LIFETIME)
  end

  private_class_method :refusals, :store
end
