# frozen_string_literal: true

require 'digest'
require_relative '../model_spec_helper'
require_relative '../../lib/sign_in_grant'

describe SignInGrant do
  cover 'SignInGrant*'

  before do
    @now = Time.now
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @payments = team_with('Payments')
    @mobile = team_with('Mobile')
    @ops = team_with('Ops', working: false)
    @request = OauthRequest::Request.new(
      client_id: 'https://claude.ai/oauth/claude-code-client-metadata', redirect_uri: 'http://localhost:4000/callback',
      state: 'abc', challenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM', resource: "#{ENV.fetch('BASE_URL')}/mcp",
      name: 'Claude Code', recognised: true
    )
  end

  def team_with(name, working: true)
    team = Team.create(name: name)
    TeamMembership.create(team_id: team.id, person_id: @alice.id, working: working)
    team
  end

  def sign_in(*teams)
    SignInGrant.call(person: @alice, request: @request, team_ids: teams.map(&:id), now: @now)
  end

  def grant
    OauthGrant.first(person_id: @alice.id)
  end

  def code_row(code)
    DB[:oauth_codes].first(code_hash: Digest::SHA256.hexdigest(code))
  end

  it "gives the app a grant for the teams ticked, as the person, for this install's MCP endpoint" do
    result = sign_in(@mobile)

    assert_predicate result, :success?
    assert_equal [@request.client_id, 'mainline:read', @request.resource], [grant.client_id, grant.scope, grant.resource]
    assert_equal([@mobile.id], BypassRLS.call { DB[:oauth_grant_teams].where(grant_id: grant.id).select_map(:team_id) })
  end

  it 'names the grant after the app, as the consent page names it' do
    sign_in(@mobile)

    assert_equal 'Claude Code', grant.name
  end

  it 'leaves an app it does not recognise unnamed, to be known by its site' do
    @request = OauthRequest::Request.new(**@request.to_h, client_id: 'https://agent.example/client.json', name: 'Claude',
      recognised: false)

    sign_in(@mobile)

    assert_nil grant.name
  end

  it 'gives a code for the grant, kept only as a digest, for a minute, bound to what was asked' do
    code = sign_in(@payments).code
    row = code_row(code)

    assert_equal [grant.id, @request.client_id, @request.redirect_uri, @request.challenge, @request.resource],
      row.values_at(:grant_id, :client_id, :redirect_uri, :code_challenge, :resource)
    assert_in_delta (@now + 60).to_f, row[:expires_at].to_f, 1
    assert_nil row[:used_at]
    assert_nil DB[:oauth_codes].first(code_hash: code)
  end

  it 'gives a different code each time, 32 random bytes long' do
    code = sign_in(@payments).code

    refute_equal code, sign_in(@payments).code
    assert_equal 43, code.length
  end

  it 'needs a team ticked, and gives nothing without one' do
    [[], nil].each do |team_ids|
      result = SignInGrant.call(person: @alice, request: @request, team_ids: team_ids, now: @now)

      refute_predicate result, :success?
      refute_empty result.errors
      assert_nil result.code
      assert_nil grant
    end
  end

  it 'refuses a team whose maps the person cannot open, and gives nothing' do
    [[@ops], [@payments, @ops]].each do |teams|
      result = sign_in(*teams)

      refute_predicate result, :success?
      assert_nil grant
    end
  end

  it 'counts a team ticked twice once' do
    SignInGrant.call(person: @alice, request: @request, team_ids: [@mobile.id, @mobile.id], now: @now)

    assert_equal(1, BypassRLS.call { DB[:oauth_grant_teams].where(grant_id: grant.id).count })
  end
end
