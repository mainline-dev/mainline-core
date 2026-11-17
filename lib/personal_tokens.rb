# frozen_string_literal: true

require 'uri'
require_relative 'bypass_rls'

# What a person's Coding agents page lists, newest first. Their personal
# tokens: the name, the teams by name, the last day it works, and when a
# coding agent last used it. And the apps they signed in that can still read:
# the app, its teams, and when it was signed in and last used.
module PersonalTokens
  Listed = Struct.new(:id, :name, :teams, :expires_on, :last_used_at, keyword_init: true)
  App = Struct.new(:id, :app, :teams, :signed_in_at, :last_used_at, keyword_init: true)

  def self.of(person)
    grants = OauthGrant.where(person_id: person.id, client_id: nil, revoked_at: nil).order(Sequel.desc(:created_at)).all
    names = team_names(grants.map(&:id))
    grants.map { |grant|
      Listed.new(id: grant.id, name: grant.name, teams: names.fetch(grant.id, []).sort,
        expires_on: grant.expires_at.getutc.to_date - 1, last_used_at: grant.last_used_at)
    }
  end

  # An app's sign-in can still read while it is not revoked and holds a
  # refresh token not yet spent or run out; a personal token never holds one.
  # A recognised app is named as it names itself; any other by its site.
  def self.apps_of(person, now:)
    working = DB[:oauth_refresh_tokens].where(used_at: nil).where(Sequel[:expires_at] > now).select(:grant_id)
    grants = OauthGrant.where(person_id: person.id, revoked_at: nil, id: working).order(Sequel.desc(:created_at)).all
    names = team_names(grants.map(&:id))
    grants.map { |grant|
      App.new(id: grant.id, app: grant.name || URI(grant.client_id).host, teams: names.fetch(grant.id, []).sort,
        signed_in_at: grant.created_at, last_used_at: grant.last_used_at)
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
