# frozen_string_literal: true

require 'date'
require_relative 'bypass_rls'
require_relative 'map_access'
require_relative 'oauth_metadata'
require_relative 'personal_token'

# Makes a person a personal token: read-only, for the teams they ticked whose
# maps they can open, through the day they chose, at most a year ahead. The
# token is given back once; only its digest is kept.
module CreatePersonalToken
  NAME_LENGTH = 100

  Result = Struct.new(:token, :errors) do
    def success?
      errors.empty?
    end
  end

  def self.call(person:, name:, team_ids:, expires_on:, today: Date.today)
    name = name.to_s.strip
    team_ids = Array(team_ids).uniq
    errors = refusals(person, name, team_ids, expires_on, today)
    return Result.new(nil, errors) unless errors.empty?

    token = PersonalToken.generate
    store(person, name, team_ids, token, ends_at(expires_on))
    Result.new(token, [])
  end

  def self.refusals(person, name, team_ids, expires_on, today)
    [
      ('Give the token a name.' if name.empty?),
      ("Keep the name to #{NAME_LENGTH} characters." if name.length > NAME_LENGTH),
      ('Tick at least one team.' if team_ids.empty?),
      ('Tick only teams whose maps you can open.' unless (team_ids - MapAccess.team_ids_for(person.id)).empty?),
      ('Choose an expiry date after today, at most a year ahead.' unless allowed_expiry?(expires_on, today))
    ].compact
  end

  def self.allowed_expiry?(expires_on, today)
    ((today + 1)..today.next_year).cover?(expires_on)
  end

  # A token lasts through the day chosen, so it ends as that day is over.
  def self.ends_at(expires_on)
    after = expires_on + 1
    Time.utc(after.year, after.month, after.day)
  end

  def self.store(person, name, team_ids, token, ends)
    DB.transaction do
      grant = OauthGrant.create(person_id: person.id, name: name, scope: OAuthMetadata::SCOPE,
        resource: OAuthMetadata.protected_resource[:resource], expires_at: ends)
      BypassRLS.call { team_ids.each { |team_id| DB[:oauth_grant_teams].insert(grant_id: grant.id, team_id: team_id) } }
      DB[:oauth_access_tokens].insert(grant_id: grant.id, token_hash: PersonalToken.digest(token), expires_at: ends)
    end
  end

  private_class_method :refusals, :allowed_expiry?, :ends_at, :store
end
