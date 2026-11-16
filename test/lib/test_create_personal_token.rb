# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_personal_token'

describe CreatePersonalToken do
  cover 'CreatePersonalToken*'

  before do
    @today = Date.new(2030, 3, 10)
    @payments = Team.create(name: 'Payments')
    @mobile = Team.create(name: 'Mobile')
    @ops = Team.create(name: 'Ops')
    @alice = Person.create(name: 'Alice', email: 'alice@tokens.co')
    TeamMembership.create(team_id: @payments.id, person_id: @alice.id, working: true)
    TeamMembership.create(team_id: @mobile.id, person_id: @alice.id, working: true)
    TeamMembership.create(team_id: @ops.id, person_id: @alice.id, working: false)
  end

  def create(name: 'build runner', teams: [@payments], expires_on: @today + 30)
    CreatePersonalToken.call(person: @alice, name: name, team_ids: teams.map(&:id), expires_on: expires_on,
      today: @today)
  end

  def grants
    OauthGrant.where(person_id: @alice.id).all
  end

  it 'gives the person a token, kept only as its digest, for the teams they ticked until the day they chose' do
    result = create(teams: [@payments, @mobile])
    grant = grants.first

    assert_predicate result, :success?
    assert PersonalToken.well_formed?(result.token)
    assert_equal ['build runner', 'mainline:read', "#{ENV.fetch('BASE_URL')}/mcp", nil],
      grant.values.values_at(:name, :scope, :resource, :client_id)
    assert_equal([@mobile.id, @payments.id].sort,
      BypassRLS.call { OauthGrantTeam.where(grant_id: grant.id).select_map(:team_id).sort })
    assert_equal [PersonalToken.digest(result.token)], OauthAccessToken.where(grant_id: grant.id).select_map(:token_hash)
  end

  it 'lasts through the day chosen and ends as it is over' do
    create(expires_on: @today + 30)

    ends = Time.utc(2030, 4, 10)

    assert_equal [ends, ends], [grants.first.expires_at, OauthAccessToken.first(grant_id: grants.first.id).expires_at]
  end

  it 'counts a team ticked twice once' do
    create(teams: [@payments, @payments])

    assert_equal(1, BypassRLS.call { OauthGrantTeam.where(grant_id: grants.first.id).count })
  end

  it 'trims the name' do
    create(name: '  laptop  ')

    assert_equal 'laptop', grants.first.name
  end

  it 'refuses a token with no name, or a name over 100 characters' do
    refute_predicate create(name: '  '), :success?
    refute_predicate create(name: 'x' * 101), :success?
    assert_predicate create(name: 'x' * 100), :success?
    assert_equal 1, grants.size
  end

  it 'refuses a token for no team' do
    result = create(teams: [])

    refute_predicate result, :success?
    assert_nil result.token
    assert_empty grants
  end

  it 'refuses a team whose maps the person cannot open' do
    refute_predicate create(teams: [@payments, @ops]), :success?
    assert_empty grants
  end

  it 'refuses a day that is not after today, or more than a year ahead, or no day at all' do
    refute_predicate create(expires_on: @today), :success?
    refute_predicate create(expires_on: @today.next_year + 1), :success?
    refute_predicate create(expires_on: nil), :success?
    assert_predicate create(expires_on: @today.next_year), :success?
    assert_equal 1, grants.size
  end

  it 'allows a token that works until tomorrow' do
    assert_predicate create(expires_on: @today + 1), :success?
  end

  it 'refuses a token given no name or no teams at all' do
    nameless = CreatePersonalToken.call(person: @alice, name: nil, team_ids: [@payments.id], expires_on: @today + 30,
      today: @today)
    teamless = CreatePersonalToken.call(person: @alice, name: 'laptop', team_ids: nil, expires_on: @today + 30,
      today: @today)

    refute_predicate nameless, :success?
    refute_predicate teamless, :success?
  end

  it 'says why, once, for each thing that is wrong' do
    refused = [create(name: ' '), create(name: 'x' * 101), create(teams: []), create(teams: [@ops]),
               create(expires_on: @today)]

    assert(refused.all? { |result| result.errors.size == 1 && !result.errors.first.empty? })
  end
end
