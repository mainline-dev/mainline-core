# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A personal token lets a coding agent that cannot sign in through a browser,
# such as one on a build runner, read the maps of the teams its person ticked.
# It is made on the person's Coding agents page and shown once.
describe 'Personal tokens' do
  include MainlineDSL

  before do
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    @mobile = another_team('Mobile')
    add_member(@alice, @mobile)
    @ops = another_team('Ops')
    add_member(@alice, @ops, working: false)
  end

  it 'offers a tick box, ticked, for each team whose maps the person can open' do
    assert_equal({ 'Mobile' => true, 'Payments' => true }, token_teams_offered)
  end

  it 'ticks only the team the form was opened for' do
    assert_equal({ 'Mobile' => true, 'Payments' => false }, token_teams_offered(for_team: @mobile))
  end

  it 'ticks every team when the form is opened for a team whose maps the person cannot open' do
    assert_equal({ 'Mobile' => true, 'Payments' => true }, token_teams_offered(for_team: @ops))
  end

  it 'shows a new token once, then lists it by name with its teams, its expiry and no use yet' do
    expires_on = Date.today + 30

    token = create_personal_token(name: 'build runner', teams: [@team], expires_on: expires_on)

    assert_match(/\Amainline_pat_/, token)
    refute_includes visit_coding_agents.body, token
    assert_equal [{ name: 'build runner', teams: ['Payments'], expires_on: expires_on.iso8601, last_used: nil }],
      personal_tokens_listed
  end

  it 'refuses a token for no team' do
    assert_nil create_personal_token(name: 'build runner', teams: [], expires_on: Date.today + 30)
    assert_empty personal_tokens_listed
  end

  it 'refuses a token that would last more than a year, or that has already run out' do
    assert_nil create_personal_token(name: 'build runner', teams: [@team], expires_on: Date.today.next_year + 1)
    assert_nil create_personal_token(name: 'build runner', teams: [@team], expires_on: Date.today)
    assert_empty personal_tokens_listed
  end

  it 'refuses a token without a name' do
    assert_nil create_personal_token(name: ' ', teams: [@team], expires_on: Date.today + 30)
  end

  it 'refuses a team whose maps the person cannot open, even when the form is changed to name it' do
    assert_nil create_personal_token(name: 'build runner', teams: [@ops], expires_on: Date.today + 30)
    assert_empty personal_tokens_listed
  end
end
