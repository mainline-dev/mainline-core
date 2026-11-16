# frozen_string_literal: true

require_relative 'bypass_rls'

# A person's personal tokens as their Coding agents page lists them, newest
# first: the name, the teams by name, the last day it works, and when a coding
# agent last used it. Revoked tokens and OAuth sign-ins are not listed here.
module PersonalTokens
  Listed = Struct.new(:id, :name, :teams, :expires_on, :last_used_at, keyword_init: true)

  def self.of(person)
    grants = OauthGrant.where(person_id: person.id, client_id: nil, revoked_at: nil).order(Sequel.desc(:created_at)).all
    names = team_names(grants.map(&:id))
    grants.map { |grant|
      Listed.new(id: grant.id, name: grant.name, teams: names.fetch(grant.id, []).sort,
        expires_on: grant.expires_at.getutc.to_date - 1, last_used_at: grant.last_used_at)
    }
  end

  def self.team_names(grant_ids)
    rows = BypassRLS.call {
      DB[:oauth_grant_teams].join(:teams, id: :team_id).where(grant_id: grant_ids)
        .select_map(%i[grant_id name])
    }
    rows.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end
  private_class_method :team_names
end
