# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

# How often /mcp answers before it says "too many". A token Mainline issued
# counts against its own grant, whether it still works or has expired or been
# revoked, so the many people who reach Mainline from one platform's
# addresses never use up each other's allowance. Only a token that matches
# nothing counts against the address it came from.
describe 'Limits at /mcp' do
  include MainlineDSL
  include McpDSL

  before do
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
  end

  after { back_to_today }

  def token(name = 'build runner', days: 30)
    create_personal_token(name: name, teams: [@team], expires_on: Date.today + days)
  end

  it 'answers 50 different grants\' expired tokens from one address with 401s, never a 429' do
    tokens = Array.new(50) { |n| token("runner #{n}") }
    days_pass(31)

    statuses = tokens.map { |expired| connect_mcp(token: expired, from: '160.79.104.10').status }

    assert_equal [401], statuses.uniq
  end

  it 'answers a token that matches nothing 600 times an hour from one address, then turns that address away' do
    the_clock_stops
    statuses = Array.new(601) { connect_mcp(token: 'not-a-token', from: '203.0.113.7').status }

    assert_equal [401], statuses.first(600).uniq
    assert_equal 429, statuses.last
    assert_equal 401, connect_mcp(token: 'not-a-token', from: '203.0.113.8').status
  end

  it 'takes 120 calls a minute with a live token, then says when to try again' do
    live = token
    the_clock_stops

    statuses = Array.new(121) { call_mcp('list_maps', token: live).status }

    assert_equal [200], statuses.first(120).uniq
    assert_equal 429, statuses.last
    refute_nil last_answer_header('Retry-After')
    assert_equal 200, call_mcp('list_maps', token: token('laptop')).status
  end

  it "counts an expired token's refusals against its own grant, and no other" do
    expiring = token('old runner', days: 1)
    days_pass(2)
    live = token('new runner')
    the_clock_stops

    statuses = Array.new(121) { connect_mcp(token: expiring).status }

    assert_equal [401], statuses.first(120).uniq
    assert_equal 429, statuses.last
    assert_equal 200, connect_mcp(token: live).status
  end
end
