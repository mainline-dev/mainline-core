# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_personal_token'
require_relative '../../lib/personal_tokens'

describe PersonalTokens do
  cover 'PersonalTokens*'

  before do
    @today = Date.new(2030, 3, 10)
    @payments = Team.create(name: 'Payments')
    @mobile = Team.create(name: 'Mobile')
    @alice = Person.create(name: 'Alice', email: 'alice@listed.co')
    @bob = Person.create(name: 'Bob', email: 'bob@listed.co')
    [@alice, @bob].each do |person|
      TeamMembership.create(team_id: @payments.id, person_id: person.id, working: true)
      TeamMembership.create(team_id: @mobile.id, person_id: person.id, working: true)
    end
  end

  def create(person, name, teams)
    CreatePersonalToken.call(person: person, name: name, team_ids: teams.map(&:id), expires_on: @today + 30,
      today: @today)
  end

  it "lists a person's tokens, newest first, with their teams by name, expiry and last use" do
    create(@alice, 'build runner', [@payments, @mobile])
    create(@alice, 'laptop', [@payments])
    create(@bob, 'theirs', [@payments])
    # One transaction gives both the same time, so set when each was made.
    OauthGrant.where(name: 'build runner').update(created_at: Time.utc(2020, 1, 1))
    OauthGrant.where(name: 'laptop').update(created_at: Time.utc(2020, 2, 1))

    listed = PersonalTokens.of(@alice).map { |token| token.to_h.except(:id) }

    assert_equal [{ name: 'laptop', teams: ['Payments'], expires_on: Date.new(2030, 4, 9), last_used_at: nil },
                  { name: 'build runner', teams: %w[Mobile Payments], expires_on: Date.new(2030, 4, 9), last_used_at: nil }], listed
  end

  it 'gives each token its grant, and when a coding agent last used it' do
    create(@alice, 'laptop', [@payments])
    grant = OauthGrant.first(name: 'laptop')
    used = Time.utc(2030, 3, 12, 9, 30)
    grant.update(last_used_at: used)

    listed = PersonalTokens.of(@alice).first

    assert_equal [grant.id, used], [listed.id, listed.last_used_at]
  end

  it 'lists a token whose teams are all gone with no teams' do
    create(@alice, 'laptop', [@payments])
    BypassRLS.call { OauthGrantTeam.where(team_id: @payments.id).delete }

    assert_equal [[]], PersonalTokens.of(@alice).map(&:teams)
  end

  it 'leaves out revoked tokens and OAuth sign-ins' do
    create(@alice, 'laptop', [@payments])
    OauthGrant.where(name: 'laptop').update(revoked_at: Time.now)
    OauthGrant.create(person_id: @alice.id, client_id: 'https://claude.ai/oauth/claude-code-client-metadata',
      scope: 'mainline:read', resource: "#{ENV.fetch('BASE_URL')}/mcp")

    assert_empty PersonalTokens.of(@alice)
  end
end
