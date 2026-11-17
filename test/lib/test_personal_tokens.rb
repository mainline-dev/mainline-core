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

  describe 'apps signed in' do
    before { @now = Time.utc(2030, 3, 10, 12) }

    # An app's sign-in for these teams, as signing in and swapping the code
    # leave it: a grant with a refresh token that runs out then.
    def signed_in(person, teams, name: 'Claude Code', client_id: 'https://claude.ai/oauth/claude-code-client-metadata',
                  made: @now, runs_out: @now + 86_400)
      grant = OauthGrant.create(person_id: person.id, client_id: client_id, name: name, scope: 'mainline:read',
        resource: "#{ENV.fetch('BASE_URL')}/mcp")
      grant.update(created_at: made)
      BypassRLS.call { teams.each { |team| DB[:oauth_grant_teams].insert(grant_id: grant.id, team_id: team.id) } }
      DB[:oauth_refresh_tokens].insert(grant_id: grant.id, token_hash: SecureRandom.hex(32), expires_at: runs_out)
      grant
    end

    it "lists a person's working sign-ins, newest first, with the app, its teams, and when signed in and last used" do
      claude = signed_in(@alice, [@payments], made: Time.utc(2030, 3, 1))
      codex = signed_in(@alice, [@mobile, @payments], name: 'Codex', client_id: 'https://chatgpt.com/oauth/codex/client.json',
        made: Time.utc(2030, 3, 5))
      codex.update(last_used_at: Time.utc(2030, 3, 9))

      listed = PersonalTokens.apps_of(@alice, now: @now)
      rows = listed.map { |app| app.to_h.except(:id) }

      assert_equal [codex.id, claude.id], listed.map(&:id)
      assert_equal [{ app: 'Codex', teams: %w[Mobile Payments], signed_in_at: Time.utc(2030, 3, 5), last_used_at: Time.utc(2030, 3, 9) },
                    { app: 'Claude Code', teams: ['Payments'], signed_in_at: Time.utc(2030, 3, 1), last_used_at: nil }], rows
    end

    it 'lists a sign-in whose teams are all gone with no teams' do
      signed_in(@alice, [])

      assert_equal [[]], PersonalTokens.apps_of(@alice, now: @now).map(&:teams)
    end

    it "leaves out revoked and lapsed sign-ins, personal tokens and other people's" do
      signed_in(@alice, [@payments]).update(revoked_at: @now)
      signed_in(@alice, [@payments], runs_out: @now - 1)
      create(@alice, 'build runner', [@payments])
      signed_in(@bob, [@payments])

      assert_empty PersonalTokens.apps_of(@alice, now: @now)
    end

    it 'lists a sign-in only while it holds a refresh token not yet spent' do
      grant = signed_in(@alice, [@payments])
      DB[:oauth_refresh_tokens].where(grant_id: grant.id).update(used_at: @now)

      assert_empty PersonalTokens.apps_of(@alice, now: @now)
    end

    it "names a sign-in made before names were kept by its app's site" do
      signed_in(@alice, [@payments], name: nil)

      assert_equal ['claude.ai'], PersonalTokens.apps_of(@alice, now: @now).map(&:app)
    end
  end
end
